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

typedef struct {
 UV  bits;
 I32 requires;
} a_hint_t;

STATIC SV *a_tag(pTHX_ UV bits) {
#define a_tag(B) a_tag(aTHX_ (B))
 SV *tag;
 a_hint_t h;

 h.bits = bits;

 {
  const PERL_SI *si;
  I32            requires = 0;

  for (si = PL_curstackinfo; si; si = si->si_prev) {
   I32 cxix;

   for (cxix = si->si_cxix; cxix >= 0; --cxix) {
    const PERL_CONTEXT *cx = si->si_cxstack + cxix;

    if (CxTYPE(cx) == CXt_EVAL && cx->blk_eval.old_op_type == OP_REQUIRE)
     ++requires;
   }
  }

  h.requires = requires;
 }

 return newSVpvn((const char *) &h, sizeof h);
}

STATIC UV a_detag(pTHX_ const SV *hint) {
#define a_detag(H) a_detag(aTHX_ (H))
 const a_hint_t *h;

 if (!(hint && SvOK(hint)))
  return 0;

 h = (const a_hint_t *) SvPVX(hint);

 {
  const PERL_SI *si;
  I32            requires = 0;

  for (si = PL_curstackinfo; si; si = si->si_prev) {
   I32 cxix;

   for (cxix = si->si_cxix; cxix >= 0; --cxix) {
    const PERL_CONTEXT *cx = si->si_cxstack + cxix;

    if (CxTYPE(cx) == CXt_EVAL && cx->blk_eval.old_op_type == OP_REQUIRE
                               && ++requires > h->requires)
     return 0;
   }
  }
 }

 return h->bits;
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
#define A_HINT_DEREF  64

STATIC U32 a_hash = 0;

STATIC UV a_hint(pTHX) {
#define a_hint() a_hint(aTHX)
 const SV *hint;
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
 const OP *root;
 UV flags;
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

STATIC void a_map_store(pPTBLMS_ const OP *o, OP *(*old_pp)(pTHX), UV flags) {
#define a_map_store(O, PP, F) a_map_store(aPTBLMS_ (O), (PP), (F))
 a_op_info *oi;

#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 if (!(oi = ptable_fetch(a_op_map, o))) {
  oi = PerlMemShared_malloc(sizeof *oi);
  ptable_map_store(a_op_map, o, oi);
 }

 oi->old_pp = old_pp;
 oi->root   = NULL;
 oi->flags  = flags;

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif
}

STATIC const a_op_info *a_map_fetch(const OP *o, a_op_info *oi) {
 const a_op_info *val;

#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 val = ptable_fetch(a_op_map, o);
 if (val) {
  *oi = *val;
  val = oi;
 } else
  oi->old_pp = 0;

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif

 return val;
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

STATIC void a_map_set_root(const OP *root, UV flags) {
 a_op_info *oi;
 const OP *o = root;

#ifdef USE_ITHREADS
 MUTEX_LOCK(&a_op_map_mutex);
#endif

 while (o) {
  if (oi = ptable_fetch(a_op_map, o)) {
   oi->root  = root;
   oi->flags = flags;
  }
  if (!(o->op_flags & OPf_KIDS))
   break;
  switch (PL_opargs[o->op_type] & OA_CLASS_MASK) {
   case OA_BASEOP:
   case OA_UNOP:
   case OA_BINOP:
   case OA_BASEOP_OR_UNOP:
    o = cUNOPo->op_first;
    break;
   case OA_LIST:
   case OA_LISTOP:
    o = cLISTOPo->op_last;
    break;
   default:
    goto done;
  }
 }

done:
#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&a_op_map_mutex);
#endif

 return;
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

/* ... pp_rv2av ............................................................ */

STATIC OP *a_pp_rv2av(pTHX) {
 a_op_info oi;
 UV hint;
 dSP;

 if (!SvOK(TOPs)) {
  /* We always need to push an empty array to fool the pp_aelem() that comes
   * later. */
  SV *av;
  POPs;
  av = sv_2mortal((SV *) newAV());
  PUSHs(av);
  RETURN;
 }

 a_map_fetch(PL_op, &oi);

 return CALL_FPTR(oi.old_pp)(aTHX);
}

/* ... pp_rv2hv ............................................................ */

STATIC OP *a_pp_rv2hv(pTHX) {
 a_op_info oi;
 UV hint;
 dSP;

 a_map_fetch(PL_op, &oi);

 if (!SvOK(TOPs)) {
  if (oi.root->op_flags & OPf_MOD) {
   SV *hv;
   POPs;
   hv = sv_2mortal((SV *) newHV());
   PUSHs(hv);
  }
  RETURN;
 }

 return CALL_FPTR(oi.old_pp)(aTHX);
}

/* ... pp_deref (aelem,helem,rv2sv,padsv) .................................. */

STATIC const char a_msg_forbidden[]  = "Reference vivification forbidden";
STATIC const char a_msg_impossible[] = "Can't vivify reference";

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
     croak(a_msg_forbidden);
    else if (flags & A_HINT_WARN)
      warn(a_msg_forbidden);
    else /* A_HINT_STORE */
     croak(a_msg_impossible);
   }
  }

  return o;
 } else if (flags && (PL_op->op_private & OPpDEREF || PL_op == oi.root)) {
  oi.flags = flags & A_HINT_NOTIFY;

  if ((oi.root->op_flags & (OPf_MOD|OPf_REF)) != (OPf_MOD|OPf_REF)) {
   if (flags & A_HINT_FETCH)
    oi.flags |= (A_HINT_FETCH|A_HINT_DEREF);
  } else if (flags & A_HINT_STORE)
    oi.flags |= (A_HINT_STORE|A_HINT_DEREF);

  if (PL_op == oi.root)
   oi.flags &= ~A_HINT_DEREF;

  /* We will need the updated flags value in the deref part */
  flags = oi.flags;

  if (flags & A_HINT_DEREF)
   goto deref;

  /* This op doesn't need to skip autovivification, so restore the original
   * state. Be aware that another extension might have saved a_pp_deref as the
   * ppaddr for this op, so restoring PL_op->op_ppaddr doesn't ensure that this
   * function will never be called again. That's why we don't remove the op info
   * from our map and we reset oi.flags to 0, so that it can still run correctly
   * if required. */
  oi.flags = 0;
  PL_op->op_ppaddr = oi.old_pp;
 }

 return CALL_FPTR(oi.old_pp)(aTHX);
}

/* ... pp_root (exists,delete) ............................................. */

STATIC OP *a_pp_root(pTHX) {
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
  a_map_store(o, a_pp_padsv_saved, hint);
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
  a_map_store(o, o->op_ppaddr, hint);
  o->op_ppaddr = a_pp_deref;
 } else
  a_map_delete(o);

 return o;
}

/* ... ck_deref (aelem,helem,rv2sv) ........................................ */

STATIC OP *(*a_old_ck_aelem)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_helem)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_rv2sv)(pTHX_ OP *) = 0;

STATIC OP *a_ck_deref(pTHX_ OP *o) {
 OP * (*old_ck)(pTHX_ OP *o) = 0;
 UV hint;

 switch (o->op_type) {
  case OP_AELEM: old_ck = a_old_ck_aelem; break;
  case OP_HELEM: old_ck = a_old_ck_helem; break;
  case OP_RV2SV: old_ck = a_old_ck_rv2sv; break;
 }
 o = CALL_FPTR(old_ck)(aTHX_ o);

 hint = a_hint();
 if (hint & A_HINT_DO) {
  a_map_store(o, o->op_ppaddr, hint);
  o->op_ppaddr = a_pp_deref;
  a_map_set_root(o, hint);
 } else
  a_map_delete(o);

 return o;
}

/* ... ck_rv2xv (rv2av,rv2hv) .............................................. */

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

 hint = a_hint();
 if (hint & A_HINT_DO) {
  if (!(hint & A_HINT_STRICT)) {
   a_map_store(o, o->op_ppaddr, hint);
   o->op_ppaddr = new_pp;
  }
  a_map_set_root(o, hint);
 } else
  a_map_delete(o);

 return o;
}

/* ... ck_root (exists,delete) ............................................. */

STATIC OP *(*a_old_ck_exists)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_delete)(pTHX_ OP *) = 0;

STATIC OP *a_ck_root(pTHX_ OP *o) {
 OP * (*old_ck)(pTHX_ OP *o) = 0;
 bool enabled = FALSE;
 UV hint = a_hint();

 switch (o->op_type) {
  case OP_EXISTS:
   old_ck  = a_old_ck_exists;
   enabled = hint & A_HINT_EXISTS;
   break;
  case OP_DELETE:
   old_ck  = a_old_ck_delete;
   enabled = hint & A_HINT_DELETE;
   break;
 }
 o = CALL_FPTR(old_ck)(aTHX_ o);

 if (enabled) {
  a_map_set_root(o, hint | A_HINT_DEREF);
  a_map_store(o, o->op_ppaddr, hint);
  o->op_ppaddr = a_pp_root;
 } else {
  a_map_set_root(o, 0);
 }

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
