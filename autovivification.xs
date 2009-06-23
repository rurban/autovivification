/* This file is part of the autovivification Perl module.
 * See http://search.cpan.org/dist/autovivification/ */

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define __PACKAGE__     "autovivification"
#define __PACKAGE_LEN__ (sizeof(__PACKAGE__)-1)

/* --- Compatibility wrappers ---------------------------------------------- */

#define A_HAS_PERL(R, V, S) (PERL_REVISION > (R) || (PERL_REVISION == (R) && (PERL_VERSION > (V) || (PERL_VERSION == (V) && (PERL_SUBVERSION >= (S))))))

#ifndef A_WORKAROUND_REQUIRE_PROPAGATION
# define A_WORKAROUND_REQUIRE_PROPAGATION !A_HAS_PERL(5, 10, 1)
#endif

/* --- Helpers ------------------------------------------------------------- */

#if A_WORKAROUND_REQUIRE_PROPAGATION

#define A_ENCODE_UV(B, U)   \
 len = 0;                   \
 while (len < sizeof(UV)) { \
  (B)[len++] = (U) & 0xFF;  \
  (U) >>= 8;                \
 }

#define A_DECODE_UV(U, B)        \
 len = sizeof(UV);               \
 while (len > 0)                 \
  (U) = ((U) << 8) | (B)[--len];

STATIC SV *a_tag(pTHX_ UV bits) {
#define a_tag(B) a_tag(aTHX_ (B))
 SV            *hint;
 const PERL_SI *si;
 UV             requires = 0;
 unsigned char  buf[sizeof(UV) * 2];
 STRLEN         len;

 for (si = PL_curstackinfo; si; si = si->si_prev) {
  I32 cxix;

  for (cxix = si->si_cxix; cxix >= 0; --cxix) {
   const PERL_CONTEXT *cx = si->si_cxstack + cxix;

   if (CxTYPE(cx) == CXt_EVAL && cx->blk_eval.old_op_type == OP_REQUIRE)
    ++requires;
  }
 }

 A_ENCODE_UV(buf,              requires);
 A_ENCODE_UV(buf + sizeof(UV), bits);
 hint = newSVpvn(buf, sizeof buf);
 SvREADONLY_on(hint);

 return hint;
}

STATIC UV a_detag(pTHX_ const SV *hint) {
#define a_detag(H) a_detag(aTHX_ (H))
 const PERL_SI *si;
 UV             requires = 0, requires_max = 0, bits = 0;
 unsigned char *buf;
 STRLEN         len;

 if (!(hint && SvOK(hint)))
  return 0;

 buf = SvPVX(hint);
 A_DECODE_UV(requires_max, buf);

 for (si = PL_curstackinfo; si; si = si->si_prev) {
  I32 cxix;

  for (cxix = si->si_cxix; cxix >= 0; --cxix) {
   const PERL_CONTEXT *cx = si->si_cxstack + cxix;

   if (CxTYPE(cx) == CXt_EVAL && cx->blk_eval.old_op_type == OP_REQUIRE
                              && ++requires > requires_max)
    return 0;
  }
 }

 A_DECODE_UV(bits, buf + sizeof(UV));

 return bits;
}

#else /* A_WORKAROUND_REQUIRE_PROPAGATION */

#define a_tag(B)   newSVuv(B)
#define a_detag(H) (((H) && SvOK(H)) ? SvUVX(H) : 0)

#endif /* !A_WORKAROUND_REQUIRE_PROPAGATION */

/* Used both for hints and op flags */
#define A_HINT_STRICT 1
#define A_HINT_WARN   2
#define A_HINT_FETCH  4
#define A_HINT_STORE  8
#define A_HINT_EXISTS 16
#define A_HINT_DELETE 32
#define A_HINT_NOTIFY (A_HINT_STRICT|A_HINT_WARN)
#define A_HINT_DO     (A_HINT_FETCH|A_HINT_STORE|A_HINT_EXISTS|A_HINT_DELETE)
#define A_HINT_MASK   (A_HINT_NOTIFY|A_HINT_DO)

/* Only used in op flags */
#define A_HINT_ROOT   64
#define A_HINT_DEREF  128

STATIC U32 a_hash = 0;

STATIC UV a_hint(pTHX) {
#define a_hint() a_hint(aTHX)
 SV *hint;
#if A_HAS_PERL(5, 9, 5)
 hint = Perl_refcounted_he_fetch(aTHX_ PL_curcop->cop_hints_hash,
                                       NULL,
                                       __PACKAGE__, __PACKAGE_LEN__,
                                       0,
                                       a_hash);
#else
 SV **val = hv_fetch(GvHV(PL_hintgv), __PACKAGE__, __PACKAGE_LEN__, a_hash);
 if (!val)
  return 0;
 hint = *val;
#endif
 return a_detag(hint);
}

/* ... op => info map ...................................................... */

typedef struct {
 OP *(*old_pp)(pTHX);
 UV flags;
 void *next;
} a_op_info;

#define PTABLE_NAME        ptable_map
#define PTABLE_VAL_FREE(V) PerlMemShared_free(V)

#include "ptable.h"

/* PerlMemShared_free() needs the [ap]PTBLMS_? default values */
#define ptable_map_store(T, K, V) ptable_map_store(aPTBLMS_ (T), (K), (V))

STATIC ptable *a_op_map = NULL;

#ifdef USE_ITHREADS
STATIC perl_mutex a_op_map_mutex;
#endif

STATIC const a_op_info *a_map_fetch(const OP *o, a_op_info *oi) {
 const a_op_info *val;

#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 val = ptable_fetch(a_op_map, o);
 if (val) {
  *oi = *val;
  val = oi;
 }

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif

 return val;
}

STATIC const a_op_info *a_map_store_locked(pPTBLMS_ const OP *o, OP *(*old_pp)(pTHX), void *next, UV flags) {
#define a_map_store_locked(O, PP, N, F) a_map_store_locked(aPTBLMS_ (O), (PP), (N), (F))
 a_op_info *oi;

 if (!(oi = ptable_fetch(a_op_map, o))) {
  oi = PerlMemShared_malloc(sizeof *oi);
  ptable_map_store(a_op_map, o, oi);
 }

 oi->old_pp = old_pp;
 oi->next   = next;
 oi->flags  = flags;

 return oi;
}

STATIC void a_map_store(pPTBLMS_ const OP *o, OP *(*old_pp)(pTHX), void *next, UV flags) {
#define a_map_store(O, PP, N, F) a_map_store(aPTBLMS_ (O), (PP), (N), (F))

#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 a_map_store_locked(o, old_pp, next, flags);

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif
}

STATIC void a_map_delete(pTHX_ const OP *o) {
#define a_map_delete(O) a_map_delete(aTHX_ (O))
#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 ptable_map_store(a_op_map, o, NULL);

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif
}

STATIC const OP *a_map_descend(const OP *o) {
 switch (PL_opargs[o->op_type] & OA_CLASS_MASK) {
  case OA_BASEOP:
  case OA_UNOP:
  case OA_BINOP:
  case OA_BASEOP_OR_UNOP:
   return cUNOPo->op_first;
  case OA_LIST:
  case OA_LISTOP:
   return cLISTOPo->op_last;
 }

 return NULL;
}

STATIC void a_map_store_root(pPTBLMS_ const OP *root, OP *(*old_pp)(pTHX), UV flags) {
#define a_map_store_root(R, PP, F) a_map_store_root(aPTBLMS_ (R), (PP), (F))
 const a_op_info *roi;
 a_op_info *oi;
 const OP *o = root;

#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 roi = a_map_store_locked(o, old_pp, (OP *) root, flags | A_HINT_ROOT);

 while (o->op_flags & OPf_KIDS) {
  o = a_map_descend(o);
  if (!o)
   break;
  if ((oi = ptable_fetch(a_op_map, o))) {
   oi->flags &= ~A_HINT_ROOT;
   oi->next   = (a_op_info *) roi;
   break;
  }
 }

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif

 return;
}

STATIC void a_map_update_flags_topdown(const OP *root, UV flags) {
 a_op_info *oi;
 const OP *o = root;

#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 flags &= ~A_HINT_ROOT;

 do {
  if ((oi = ptable_fetch(a_op_map, o)))
   oi->flags = (oi->flags & A_HINT_ROOT) | flags;
  if (!(o->op_flags & OPf_KIDS))
   break;
  o = a_map_descend(o);
 } while (o);

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif

 return;
}

#define a_map_cancel(R) a_map_update_flags_topdown((R), 0)

STATIC void a_map_update_flags_bottomup(const OP *o, UV flags, UV rflags) {
 a_op_info *oi;

#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 flags  &= ~A_HINT_ROOT;
 rflags |=  A_HINT_ROOT;

 oi = ptable_fetch(a_op_map, o);
 while (!(oi->flags & A_HINT_ROOT)) {
  oi->flags = flags;
  oi        = oi->next;
 }
 oi->flags = rflags;

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif

 return;
}

/* ... Decide whether this expression should be autovivified or not ........ */

STATIC UV a_map_resolve(const OP *o, a_op_info *oi) {
 UV flags = 0, rflags;
 const OP *root;
 a_op_info *roi = oi;

 while (!(roi->flags & A_HINT_ROOT))
  roi = roi->next;
 if (!roi)
  goto cancel;

 rflags = roi->flags & ~A_HINT_ROOT;
 if (!rflags)
  goto cancel;

 root = roi->next;
 if (root->op_flags & OPf_MOD) {
  if (rflags & A_HINT_STORE)
   flags = (A_HINT_STORE|A_HINT_DEREF);
 } else if (rflags & A_HINT_FETCH)
   flags = (A_HINT_FETCH|A_HINT_DEREF);

 if (!flags) {
cancel:
  a_map_update_flags_bottomup(o, 0, 0);
  return 0;
 }

 flags |= (rflags & A_HINT_NOTIFY);
 a_map_update_flags_bottomup(o, flags, 0);

 return oi->flags & A_HINT_ROOT ? 0 : flags;
}

/* ... Lightweight pp_defined() ............................................ */

STATIC bool a_defined(pTHX_ SV *sv) {
#define a_defined(S) a_defined(aTHX_ (S))
 bool defined = FALSE;

 switch (SvTYPE(sv)) {
  case SVt_PVAV:
   if (AvMAX(sv) >= 0 || SvGMAGICAL(sv)
                      || (SvRMAGICAL(sv) && mg_find(sv, PERL_MAGIC_tied)))
    defined = TRUE;
   break;
  case SVt_PVHV:
   if (HvARRAY(sv) || SvGMAGICAL(sv)
                   || (SvRMAGICAL(sv) && mg_find(sv, PERL_MAGIC_tied)))
    defined = TRUE;
   break;
  default:
   defined = SvOK(sv);
 }

 return defined;
}

/* --- PP functions -------------------------------------------------------- */

/* Be aware that we restore PL_op->op_ppaddr from the pointer table old_pp
 * value, another extension might have saved our pp replacement as the ppaddr
 * for this op, so this doesn't ensure that our function will never be called
 * again. That's why we don't remove the op info from our map, so that it can
 * still run correctly if required. */

/* ... pp_rv2av ............................................................ */

STATIC OP *a_pp_rv2av(pTHX) {
 a_op_info oi;
 UV flags;
 dSP;

 a_map_fetch(PL_op, &oi);
 flags = oi.flags;

 if (flags & A_HINT_DEREF) {
  if (!SvOK(TOPs)) {
   /* We always need to push an empty array to fool the pp_aelem() that comes
    * later. */
   SV *av;
   POPs;
   av = sv_2mortal((SV *) newAV());
   PUSHs(av);
   RETURN;
  }
 } else {
  PL_op->op_ppaddr = oi.old_pp;
 }

 return CALL_FPTR(oi.old_pp)(aTHX);
}

/* ... pp_rv2hv ............................................................ */

STATIC OP *a_pp_rv2hv(pTHX) {
 a_op_info oi;
 UV flags;
 dSP;

 a_map_fetch(PL_op, &oi);
 flags = oi.flags;

 if (flags & A_HINT_DEREF) {
  if (!SvOK(TOPs))
   RETURN;
 } else {
  PL_op->op_ppaddr = oi.old_pp;
 }

 return CALL_FPTR(oi.old_pp)(aTHX);
}

/* ... pp_deref (aelem,helem,rv2sv,padsv) .................................. */

STATIC OP *a_pp_deref(pTHX) {
 a_op_info oi;
 UV flags;
 dSP;

 a_map_fetch(PL_op, &oi);
 flags = oi.flags;

 if (flags & A_HINT_DEREF) {
  OP *o;
  U8 old_private;

deref:
  old_private       = PL_op->op_private;
  PL_op->op_private = ((old_private & ~OPpDEREF) | OPpLVAL_DEFER);
  o = CALL_FPTR(oi.old_pp)(aTHX);
  PL_op->op_private = old_private;

  if (flags & (A_HINT_NOTIFY|A_HINT_STORE)) {
   SPAGAIN;
   if (!SvOK(TOPs)) {
    if (flags & A_HINT_STRICT)
     croak("Reference vivification forbidden");
    else if (flags & A_HINT_WARN)
      warn("Reference was vivified");
    else /* A_HINT_STORE */
     croak("Can't vivify reference");
   }
  }

  return o;
 } else if ((flags & ~A_HINT_ROOT)
                    && (PL_op->op_private & OPpDEREF || flags & A_HINT_ROOT)) {
  /* Decide if the expression must autovivify or not.
   * This branch should be called only once by expression. */
  flags = a_map_resolve(PL_op, &oi);

  /* We need the updated flags value in the deref branch. */
  if (flags & A_HINT_DEREF)
   goto deref;
 }

 /* This op doesn't need to skip autovivification, so restore the original
  * state. */
 PL_op->op_ppaddr = oi.old_pp;

 return CALL_FPTR(oi.old_pp)(aTHX);
}

/* ... pp_root (exists,delete,keys,values) ................................. */

STATIC OP *a_pp_root_unop(pTHX) {
 a_op_info oi;
 dSP;

 if (!a_defined(TOPs)) {
  POPs;
  /* Can only be reached by keys or values */
  if (GIMME_V == G_SCALAR) {
   dTARGET;
   PUSHi(0);
  }
  RETURN;
 }

 a_map_fetch(PL_op, &oi);

 return CALL_FPTR(oi.old_pp)(aTHX);
}

STATIC OP *a_pp_root_binop(pTHX) {
 a_op_info oi;
 dSP;

 if (!a_defined(TOPm1s)) {
  POPs;
  POPs;
  if (PL_op->op_type == OP_EXISTS)
   RETPUSHNO;
  else
   RETPUSHUNDEF;
 }

 a_map_fetch(PL_op, &oi);

 return CALL_FPTR(oi.old_pp)(aTHX);
}

/* --- Check functions ----------------------------------------------------- */

/* ... ck_pad{any,sv} ...................................................... */

/* Sadly, the PADSV OPs we are interested in don't trigger the padsv check
 * function, but are instead manually mutated from a PADANY. This is why we set
 * PL_ppaddr[OP_PADSV] in the padany check function so that PADSV OPs will have
 * their op_ppaddr set to our pp_padsv. PL_ppaddr[OP_PADSV] is then reset at the
 * beginning of every ck_pad{any,sv}. Some unwanted OPs can still call our
 * pp_padsv, but much less than if we would have set PL_ppaddr[OP_PADSV]
 * globally. */

STATIC OP *(*a_pp_padsv_saved)(pTHX) = 0;

STATIC void a_pp_padsv_save(void) {
 if (a_pp_padsv_saved)
  return;

 a_pp_padsv_saved    = PL_ppaddr[OP_PADSV];
 PL_ppaddr[OP_PADSV] = a_pp_deref;
}

STATIC void a_pp_padsv_restore(OP *o) {
 if (!a_pp_padsv_saved)
  return;

 if (o->op_ppaddr == a_pp_deref)
  o->op_ppaddr = a_pp_padsv_saved;

 PL_ppaddr[OP_PADSV] = a_pp_padsv_saved;
 a_pp_padsv_saved    = 0;
}

STATIC OP *(*a_old_ck_padany)(pTHX_ OP *) = 0;

STATIC OP *a_ck_padany(pTHX_ OP *o) {
 UV hint;

 a_pp_padsv_restore(o);

 o = CALL_FPTR(a_old_ck_padany)(aTHX_ o);

 hint = a_hint();
 if (hint & A_HINT_DO) {
  a_pp_padsv_save();
  a_map_store_root(o, a_pp_padsv_saved, hint);
 } else
  a_map_delete(o);

 return o;
}

STATIC OP *(*a_old_ck_padsv)(pTHX_ OP *) = 0;

STATIC OP *a_ck_padsv(pTHX_ OP *o) {
 UV hint;

 a_pp_padsv_restore(o);

 o = CALL_FPTR(a_old_ck_padsv)(aTHX_ o);

 hint = a_hint();
 if (hint & A_HINT_DO) {
  a_map_store_root(o, o->op_ppaddr, hint);
  o->op_ppaddr = a_pp_deref;
 } else
  a_map_delete(o);

 return o;
}

/* ... ck_deref (aelem,helem,rv2sv) ........................................ */

/* Those ops appear both at the root and inside an expression but there's no
 * way to distinguish both situations. Worse, we can't even know if we are in a
 * modifying context, so the expression can't be resolved yet. It will be at the
 * first invocation of a_pp_deref() for this expression. */

STATIC OP *(*a_old_ck_aelem)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_helem)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_rv2sv)(pTHX_ OP *) = 0;

STATIC OP *a_ck_deref(pTHX_ OP *o) {
 OP * (*old_ck)(pTHX_ OP *o) = 0;
 UV hint = a_hint();

 switch (o->op_type) {
  case OP_AELEM:
   old_ck = a_old_ck_aelem;
   if ((hint & A_HINT_DO) && !(hint & A_HINT_STRICT)) {
    OP *kid = cUNOPo->op_first;
    a_op_info oi;
    if (kid->op_type == OP_RV2AV && kid->op_ppaddr != a_pp_rv2av
                                 && kUNOP->op_first->op_type != OP_GV
                                 && a_map_fetch(kid, &oi)) {
     a_map_store(kid, kid->op_ppaddr, o, hint);
     kid->op_ppaddr = a_pp_rv2av;
    }
   }
   break;
  case OP_HELEM:
   old_ck = a_old_ck_helem;
   if ((hint & A_HINT_DO) && !(hint & A_HINT_STRICT)) {
    OP *kid = cUNOPo->op_first;
    a_op_info oi;
    if (kid->op_type == OP_RV2HV && kid->op_ppaddr != a_pp_rv2hv
                                 && kUNOP->op_first->op_type != OP_GV
                                 && a_map_fetch(kid, &oi)) {
     a_map_store(kid, kid->op_ppaddr, o, hint);
     kid->op_ppaddr = a_pp_rv2hv;
    }
   }
   break;
  case OP_RV2SV:
   old_ck = a_old_ck_rv2sv;
   break;
 }
 o = CALL_FPTR(old_ck)(aTHX_ o);

 if (hint & A_HINT_DO) {
  a_map_store_root(o, o->op_ppaddr, hint);
  o->op_ppaddr = a_pp_deref;
 } else
  a_map_delete(o);

 return o;
}

/* ... ck_rv2xv (rv2av,rv2hv) .............................................. */

/* Those ops also appear both inisde and at the root, hence the caveats for
 * a_ck_deref() still apply here. Since a padsv/rv2sv must appear before a
 * rv2[ah]v, resolution is handled by the first call to a_pp_deref() in the
 * expression. */

STATIC OP *(*a_old_ck_rv2av)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_rv2hv)(pTHX_ OP *) = 0;

STATIC OP *a_ck_rv2xv(pTHX_ OP *o) {
 OP * (*old_ck)(pTHX_ OP *o) = 0;
 OP * (*new_pp)(pTHX)        = 0;
 UV hint;

 switch (o->op_type) {
  case OP_RV2AV: old_ck = a_old_ck_rv2av; new_pp = a_pp_rv2av; break;
  case OP_RV2HV: old_ck = a_old_ck_rv2hv; new_pp = a_pp_rv2hv; break;
 }
 o = CALL_FPTR(old_ck)(aTHX_ o);

 if (cUNOPo->op_first->op_type == OP_GV)
  return o;

 hint = a_hint();
 if (hint & A_HINT_DO && !(hint & A_HINT_STRICT)) {
  a_map_store_root(o, o->op_ppaddr, hint);
  o->op_ppaddr = new_pp;
 } else
  a_map_delete(o);

 return o;
}

/* ... ck_root (exists,delete,keys,values) ................................. */

/* Those ops are only found at the root of a dereferencing expression. We can
 * then resolve at compile time if vivification must take place or not. */

STATIC OP *(*a_old_ck_exists)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_delete)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_keys)  (pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_values)(pTHX_ OP *) = 0;

STATIC OP *a_ck_root(pTHX_ OP *o) {
 OP * (*old_ck)(pTHX_ OP *o) = 0;
 OP * (*new_pp)(pTHX)        = 0;
 bool enabled = FALSE;
 UV hint = a_hint();

 switch (o->op_type) {
  case OP_EXISTS:
   old_ck  = a_old_ck_exists;
   new_pp  = a_pp_root_binop;
   enabled = hint & A_HINT_EXISTS;
   break;
  case OP_DELETE:
   old_ck  = a_old_ck_delete;
   new_pp  = a_pp_root_binop;
   enabled = hint & A_HINT_DELETE;
   break;
  case OP_KEYS:
   old_ck  = a_old_ck_keys;
   new_pp  = a_pp_root_unop;
   enabled = hint & A_HINT_FETCH;
   break;
  case OP_VALUES:
   old_ck  = a_old_ck_values;
   new_pp  = a_pp_root_unop;
   enabled = hint & A_HINT_FETCH;
   break;
 }
 o = CALL_FPTR(old_ck)(aTHX_ o);

 if (hint & A_HINT_DO) {
  if (enabled) {
   a_map_update_flags_topdown(o, hint | A_HINT_DEREF);
   a_map_store_root(o, o->op_ppaddr, hint);
   o->op_ppaddr = new_pp;
  } else {
   a_map_cancel(o);
  }
 } else
  a_map_delete(o);

 return o;
}

STATIC U32 a_initialized = 0;

/* --- XS ------------------------------------------------------------------ */

MODULE = autovivification      PACKAGE = autovivification

PROTOTYPES: ENABLE

BOOT: 
{                                    
 if (!a_initialized++) {
  HV *stash;

  a_op_map = ptable_new();
#ifdef USE_ITHREADS
  MUTEX_INIT(&a_op_map_mutex);
#endif

  PERL_HASH(a_hash, __PACKAGE__, __PACKAGE_LEN__);

  a_old_ck_padany     = PL_check[OP_PADANY];
  PL_check[OP_PADANY] = MEMBER_TO_FPTR(a_ck_padany);
  a_old_ck_padsv      = PL_check[OP_PADSV];
  PL_check[OP_PADSV]  = MEMBER_TO_FPTR(a_ck_padsv);

  a_old_ck_aelem      = PL_check[OP_AELEM];
  PL_check[OP_AELEM]  = MEMBER_TO_FPTR(a_ck_deref);
  a_old_ck_helem      = PL_check[OP_HELEM];
  PL_check[OP_HELEM]  = MEMBER_TO_FPTR(a_ck_deref);
  a_old_ck_rv2sv      = PL_check[OP_RV2SV];
  PL_check[OP_RV2SV]  = MEMBER_TO_FPTR(a_ck_deref);

  a_old_ck_rv2av      = PL_check[OP_RV2AV];
  PL_check[OP_RV2AV]  = MEMBER_TO_FPTR(a_ck_rv2xv);
  a_old_ck_rv2hv      = PL_check[OP_RV2HV];
  PL_check[OP_RV2HV]  = MEMBER_TO_FPTR(a_ck_rv2xv);

  a_old_ck_exists     = PL_check[OP_EXISTS];
  PL_check[OP_EXISTS] = MEMBER_TO_FPTR(a_ck_root);
  a_old_ck_delete     = PL_check[OP_DELETE];
  PL_check[OP_DELETE] = MEMBER_TO_FPTR(a_ck_root);
  a_old_ck_keys       = PL_check[OP_KEYS];
  PL_check[OP_KEYS]   = MEMBER_TO_FPTR(a_ck_root);
  a_old_ck_values     = PL_check[OP_VALUES];
  PL_check[OP_VALUES] = MEMBER_TO_FPTR(a_ck_root);

  stash = gv_stashpvn(__PACKAGE__, __PACKAGE_LEN__, 1);
  newCONSTSUB(stash, "A_HINT_STRICT", newSVuv(A_HINT_STRICT));
  newCONSTSUB(stash, "A_HINT_WARN",   newSVuv(A_HINT_WARN));
  newCONSTSUB(stash, "A_HINT_FETCH",  newSVuv(A_HINT_FETCH));
  newCONSTSUB(stash, "A_HINT_STORE",  newSVuv(A_HINT_STORE));
  newCONSTSUB(stash, "A_HINT_EXISTS", newSVuv(A_HINT_EXISTS));
  newCONSTSUB(stash, "A_HINT_DELETE", newSVuv(A_HINT_DELETE));
  newCONSTSUB(stash, "A_HINT_MASK",   newSVuv(A_HINT_MASK));
 }
}

SV *
_tag(SV *hint)
PROTOTYPE: $
CODE:
 RETVAL = a_tag(SvOK(hint) ? SvUV(hint) : 0);
OUTPUT:
 RETVAL

SV *
_detag(SV *tag)
PROTOTYPE: $
CODE:
 if (!SvOK(tag))
  XSRETURN_UNDEF;
 RETVAL = newSVuv(a_detag(tag));
OUTPUT:
 RETVAL
