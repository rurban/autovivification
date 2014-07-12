/* This file is part of the autovivification Perl module.
 * See http://search.cpan.org/dist/autovivification/ */

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define __PACKAGE__     "autovivification"
#define __PACKAGE_LEN__ (sizeof(__PACKAGE__)-1)

/* --- Compatibility wrappers ---------------------------------------------- */

#ifndef HvNAME_get
# define HvNAME_get(H) HvNAME(H)
#endif

#ifndef HvNAMELEN_get
# define HvNAMELEN_get(H) strlen(HvNAME_get(H))
#endif

#define A_HAS_PERL(R, V, S) (PERL_REVISION > (R) || (PERL_REVISION == (R) && (PERL_VERSION > (V) || (PERL_VERSION == (V) && (PERL_SUBVERSION >= (S))))))

#ifndef A_WORKAROUND_REQUIRE_PROPAGATION
# define A_WORKAROUND_REQUIRE_PROPAGATION !A_HAS_PERL(5, 10, 1)
#endif

#ifndef A_HAS_RPEEP
# define A_HAS_RPEEP A_HAS_PERL(5, 13, 5)
#endif

/* ... Thread safety and multiplicity ...................................... */

/* Always safe when the workaround isn't needed */
#if !A_WORKAROUND_REQUIRE_PROPAGATION
# undef A_FORKSAFE
# define A_FORKSAFE 1
/* Otherwise, safe unless Makefile.PL says it's Win32 */
#elif !defined(A_FORKSAFE)
# define A_FORKSAFE 1
#endif

#ifndef A_MULTIPLICITY
# if defined(MULTIPLICITY) || defined(PERL_IMPLICIT_CONTEXT)
#  define A_MULTIPLICITY 1
# else
#  define A_MULTIPLICITY 0
# endif
#endif

#ifndef tTHX
# define tTHX PerlInterpreter*
#endif

#if A_MULTIPLICITY && defined(USE_ITHREADS) && defined(dMY_CXT) && defined(MY_CXT) && defined(START_MY_CXT) && defined(MY_CXT_INIT) && (defined(MY_CXT_CLONE) || defined(dMY_CXT_SV))
# define A_THREADSAFE 1
# ifndef MY_CXT_CLONE
#  define MY_CXT_CLONE \
    dMY_CXT_SV;                                                      \
    my_cxt_t *my_cxtp = (my_cxt_t*)SvPVX(newSV(sizeof(my_cxt_t)-1)); \
    Copy(INT2PTR(my_cxt_t*, SvUV(my_cxt_sv)), my_cxtp, 1, my_cxt_t); \
    sv_setuv(my_cxt_sv, PTR2UV(my_cxtp))
# endif
#else
# define A_THREADSAFE 0
# undef  dMY_CXT
# define dMY_CXT      dNOOP
# undef  MY_CXT
# define MY_CXT       a_globaldata
# undef  START_MY_CXT
# define START_MY_CXT STATIC my_cxt_t MY_CXT;
# undef  MY_CXT_INIT
# define MY_CXT_INIT  NOOP
# undef  MY_CXT_CLONE
# define MY_CXT_CLONE NOOP
#endif

#if defined(OP_CHECK_MUTEX_LOCK) && defined(OP_CHECK_MUTEX_UNLOCK)
# define A_CHECK_MUTEX_LOCK   OP_CHECK_MUTEX_LOCK
# define A_CHECK_MUTEX_UNLOCK OP_CHECK_MUTEX_UNLOCK
#else
# define A_CHECK_MUTEX_LOCK   OP_REFCNT_LOCK
# define A_CHECK_MUTEX_UNLOCK OP_REFCNT_UNLOCK
#endif

typedef OP *(*a_ck_t)(pTHX_ OP *);

#ifdef wrap_op_checker

# define a_ck_replace(T, NC, OCP) wrap_op_checker((T), (NC), (OCP))

#else

STATIC void a_ck_replace(pTHX_ OPCODE type, a_ck_t new_ck, a_ck_t *old_ck_p) {
#define a_ck_replace(T, NC, OCP) a_ck_replace(aTHX_ (T), (NC), (OCP))
 A_CHECK_MUTEX_LOCK;
 if (!*old_ck_p) {
  *old_ck_p      = PL_check[type];
  PL_check[type] = new_ck;
 }
 A_CHECK_MUTEX_UNLOCK;
}

#endif

STATIC void a_ck_restore(pTHX_ OPCODE type, a_ck_t *old_ck_p) {
#define a_ck_restore(T, OCP) a_ck_restore(aTHX_ (T), (OCP))
 A_CHECK_MUTEX_LOCK;
 if (*old_ck_p) {
  PL_check[type] = *old_ck_p;
  *old_ck_p      = 0;
 }
 A_CHECK_MUTEX_UNLOCK;
}

/* --- Helpers ------------------------------------------------------------- */

/* ... Thread-safe hints ................................................... */

#if A_WORKAROUND_REQUIRE_PROPAGATION

typedef struct {
 U32 bits;
 IV  require_tag;
} a_hint_t;

#define A_HINT_FREE(H) PerlMemShared_free(H)

#if A_THREADSAFE

#define PTABLE_NAME        ptable_hints
#define PTABLE_VAL_FREE(V) A_HINT_FREE(V)

#define pPTBL  pTHX
#define pPTBL_ pTHX_
#define aPTBL  aTHX
#define aPTBL_ aTHX_

#include "ptable.h"

#define ptable_hints_store(T, K, V) ptable_hints_store(aTHX_ (T), (K), (V))
#define ptable_hints_free(T)        ptable_hints_free(aTHX_ (T))

#endif /* A_THREADSAFE */

#endif /* A_WORKAROUND_REQUIRE_PROPAGATION */

#define PTABLE_NAME        ptable_seen
#define PTABLE_VAL_FREE(V) NOOP

#include "ptable.h"

/* PerlMemShared_free() needs the [ap]PTBLMS_? default values */
#define ptable_seen_store(T, K, V) ptable_seen_store(aPTBLMS_ (T), (K), (V))
#define ptable_seen_clear(T)       ptable_seen_clear(aPTBLMS_ (T))
#define ptable_seen_free(T)        ptable_seen_free(aPTBLMS_ (T))

#define MY_CXT_KEY __PACKAGE__ "::_guts" XS_VERSION

typedef struct {
#if A_THREADSAFE && A_WORKAROUND_REQUIRE_PROPAGATION
 ptable *tbl;   /* It really is a ptable_hints */
 tTHX    owner;
#endif /* A_THREADSAFE && A_WORKAROUND_REQUIRE_PROPAGATION */
 ptable *seen;  /* It really is a ptable_seen */
} my_cxt_t;

START_MY_CXT

#if A_THREADSAFE

#if A_WORKAROUND_REQUIRE_PROPAGATION

typedef struct {
 ptable       *tbl;
#if A_HAS_PERL(5, 13, 2)
 CLONE_PARAMS *params;
#else
 CLONE_PARAMS  params;
#endif
} a_ptable_clone_ud;

#if A_HAS_PERL(5, 13, 2)
# define a_ptable_clone_ud_init(U, T, O) \
   (U).tbl    = (T); \
   (U).params = Perl_clone_params_new((O), aTHX)
# define a_ptable_clone_ud_deinit(U) Perl_clone_params_del((U).params)
# define a_dup_inc(S, U)             SvREFCNT_inc(sv_dup((S), (U)->params))
#else
# define a_ptable_clone_ud_init(U, T, O) \
   (U).tbl               = (T);     \
   (U).params.stashes    = newAV(); \
   (U).params.flags      = 0;       \
   (U).params.proto_perl = (O)
# define a_ptable_clone_ud_deinit(U) SvREFCNT_dec((U).params.stashes)
# define a_dup_inc(S, U)             SvREFCNT_inc(sv_dup((S), &((U)->params)))
#endif

STATIC void a_ptable_clone(pTHX_ ptable_ent *ent, void *ud_) {
 a_ptable_clone_ud *ud = ud_;
 a_hint_t *h1 = ent->val;
 a_hint_t *h2;

 h2              = PerlMemShared_malloc(sizeof *h2);
 h2->bits        = h1->bits;
 h2->require_tag = PTR2IV(a_dup_inc(INT2PTR(SV *, h1->require_tag), ud));

 ptable_hints_store(ud->tbl, ent->key, h2);
}

#endif /* A_WORKAROUND_REQUIRE_PROPAGATION */

#include "reap.h"

STATIC void a_thread_cleanup(pTHX_ void *ud) {
 dMY_CXT;

#if A_WORKAROUND_REQUIRE_PROPAGATION
 ptable_hints_free(MY_CXT.tbl);
#endif /* A_WORKAROUND_REQUIRE_PROPAGATION */
 ptable_seen_free(MY_CXT.seen);
}

#endif /* A_THREADSAFE */

#if A_WORKAROUND_REQUIRE_PROPAGATION

STATIC IV a_require_tag(pTHX) {
#define a_require_tag() a_require_tag(aTHX)
 const CV *cv, *outside;

 cv = PL_compcv;

 if (!cv) {
  /* If for some reason the pragma is operational at run-time, try to discover
   * the current cv in use. */
  const PERL_SI *si;

  for (si = PL_curstackinfo; si; si = si->si_prev) {
   I32 cxix;

   for (cxix = si->si_cxix; cxix >= 0; --cxix) {
    const PERL_CONTEXT *cx = si->si_cxstack + cxix;

    switch (CxTYPE(cx)) {
     case CXt_SUB:
     case CXt_FORMAT:
      /* The propagation workaround is only needed up to 5.10.0 and at that
       * time format and sub contexts were still identical. And even later the
       * cv members offsets should have been kept the same. */
      cv = cx->blk_sub.cv;
      goto get_enclosing_cv;
     case CXt_EVAL:
      cv = cx->blk_eval.cv;
      goto get_enclosing_cv;
     default:
      break;
    }
   }
  }

  cv = PL_main_cv;
 }

get_enclosing_cv:
 for (outside = CvOUTSIDE(cv); outside; outside = CvOUTSIDE(cv))
  cv = outside;

 return PTR2IV(cv);
}

STATIC SV *a_tag(pTHX_ UV bits) {
#define a_tag(B) a_tag(aTHX_ (B))
 a_hint_t *h;

 h              = PerlMemShared_malloc(sizeof *h);
 h->bits        = bits;
 h->require_tag = a_require_tag();

#if A_THREADSAFE
 {
  dMY_CXT;
  /* We only need for the key to be an unique tag for looking up the value later
   * Allocated memory provides convenient unique identifiers, so that's why we
   * use the hint as the key itself. */
  ptable_hints_store(MY_CXT.tbl, h, h);
 }
#endif /* A_THREADSAFE */

 return newSViv(PTR2IV(h));
}

STATIC UV a_detag(pTHX_ const SV *hint) {
#define a_detag(H) a_detag(aTHX_ (H))
 a_hint_t *h;

 if (!(hint && SvIOK(hint)))
  return 0;

 h = INT2PTR(a_hint_t *, SvIVX(hint));
#if A_THREADSAFE
 {
  dMY_CXT;
  h = ptable_fetch(MY_CXT.tbl, h);
 }
#endif /* A_THREADSAFE */

 if (a_require_tag() != h->require_tag)
  return 0;

 return h->bits;
}

#else /* A_WORKAROUND_REQUIRE_PROPAGATION */

#define a_tag(B)   newSVuv(B)
/* PVs fetched from the hints chain have their SvLEN set to zero, so get the UV
 * from a copy. */
#define a_detag(H) \
 ((H)              \
  ? (SvIOK(H)      \
     ? SvUVX(H)    \
     : (SvPOK(H)   \
        ? sv_2uv(SvLEN(H) ? (H) : sv_mortalcopy(H)) \
        : 0        \
       )           \
     )             \
  : 0)

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
#ifdef cop_hints_fetch_pvn
 hint = cop_hints_fetch_pvn(PL_curcop, __PACKAGE__, __PACKAGE_LEN__, a_hash, 0);
#elif A_HAS_PERL(5, 9, 5)
 hint = Perl_refcounted_he_fetch(aTHX_ PL_curcop->cop_hints_hash,
                                       NULL,
                                       __PACKAGE__, __PACKAGE_LEN__,
                                       0,
                                       a_hash);
#else
 SV **val = hv_fetch(GvHV(PL_hintgv), __PACKAGE__, __PACKAGE_LEN__, 0);
 if (!val)
  return 0;
 hint = *val;
#endif
 return a_detag(hint);
}

/* ... op => info map ...................................................... */

typedef struct {
 OP   *(*old_pp)(pTHX);
 void   *next;
 UV      flags;
} a_op_info;

#define PTABLE_NAME        ptable_map
#define PTABLE_VAL_FREE(V) PerlMemShared_free(V)

#include "ptable.h"

/* PerlMemShared_free() needs the [ap]PTBLMS_? default values */
#define ptable_map_store(T, K, V) ptable_map_store(aPTBLMS_ (T), (K), (V))
#define ptable_map_delete(T, K)   ptable_map_delete(aPTBLMS_ (T), (K))

STATIC ptable *a_op_map = NULL;

#ifdef USE_ITHREADS

#define dA_MAP_THX a_op_info a_op_map_tmp_oi

STATIC perl_mutex a_op_map_mutex;

#define A_LOCK(M)   MUTEX_LOCK(M)
#define A_UNLOCK(M) MUTEX_UNLOCK(M)

STATIC const a_op_info *a_map_fetch(const OP *o, a_op_info *oi) {
 const a_op_info *val;

 A_LOCK(&a_op_map_mutex);

 val = ptable_fetch(a_op_map, o);
 if (val) {
  *oi = *val;
  val = oi;
 }

 A_UNLOCK(&a_op_map_mutex);

 return val;
}

#define a_map_fetch(O) a_map_fetch((O), &a_op_map_tmp_oi)

#else /* USE_ITHREADS */

#define dA_MAP_THX dNOOP

#define A_LOCK(M)   NOOP
#define A_UNLOCK(M) NOOP

#define a_map_fetch(O) ptable_fetch(a_op_map, (O))

#endif /* !USE_ITHREADS */

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
 A_LOCK(&a_op_map_mutex);

 a_map_store_locked(o, old_pp, next, flags);

 A_UNLOCK(&a_op_map_mutex);
}

STATIC void a_map_delete(pTHX_ const OP *o) {
#define a_map_delete(O) a_map_delete(aTHX_ (O))
 A_LOCK(&a_op_map_mutex);

 ptable_map_delete(a_op_map, o);

 A_UNLOCK(&a_op_map_mutex);
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

 A_LOCK(&a_op_map_mutex);

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

 A_UNLOCK(&a_op_map_mutex);

 return;
}

STATIC void a_map_update_flags_topdown(const OP *root, UV flags) {
 a_op_info *oi;
 const OP *o = root;

 A_LOCK(&a_op_map_mutex);

 flags &= ~A_HINT_ROOT;

 do {
  if ((oi = ptable_fetch(a_op_map, o)))
   oi->flags = (oi->flags & A_HINT_ROOT) | flags;
  if (!(o->op_flags & OPf_KIDS))
   break;
  o = a_map_descend(o);
 } while (o);

 A_UNLOCK(&a_op_map_mutex);

 return;
}

#define a_map_cancel(R) a_map_update_flags_topdown((R), 0)

STATIC void a_map_update_flags_bottomup(const OP *o, UV flags, UV rflags) {
 a_op_info *oi;

 A_LOCK(&a_op_map_mutex);

 flags  &= ~A_HINT_ROOT;
 rflags |=  A_HINT_ROOT;

 oi = ptable_fetch(a_op_map, o);
 while (!(oi->flags & A_HINT_ROOT)) {
  oi->flags = flags;
  oi        = oi->next;
 }
 oi->flags = rflags;

 A_UNLOCK(&a_op_map_mutex);

 return;
}

/* ... Decide whether this expression should be autovivified or not ........ */

STATIC UV a_map_resolve(const OP *o, const a_op_info *oi) {
 UV flags = 0, rflags;
 const OP *root;
 const a_op_info *roi = oi;

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

/* ... Inspired from pp_defined() .......................................... */

STATIC int a_undef(pTHX_ SV *sv) {
#define a_undef(S) a_undef(aTHX_ (S))
 switch (SvTYPE(sv)) {
  case SVt_NULL:
   return 1;
  case SVt_PVAV:
   if (AvMAX(sv) >= 0 || SvGMAGICAL(sv)
                      || (SvRMAGICAL(sv) && mg_find(sv, PERL_MAGIC_tied)))
    return 0;
   break;
  case SVt_PVHV:
   if (HvARRAY(sv) || SvGMAGICAL(sv)
                   || (SvRMAGICAL(sv) && mg_find(sv, PERL_MAGIC_tied)))
    return 0;
   break;
  default:
   SvGETMAGIC(sv);
   if (SvOK(sv))
    return 0;
 }

 return 1;
}

/* --- PP functions -------------------------------------------------------- */

/* Be aware that we restore PL_op->op_ppaddr from the pointer table old_pp
 * value, another extension might have saved our pp replacement as the ppaddr
 * for this op, so this doesn't ensure that our function will never be called
 * again. That's why we don't remove the op info from our map, so that it can
 * still run correctly if required. */

/* ... pp_rv2av ............................................................ */

STATIC OP *a_pp_rv2av(pTHX) {
 dA_MAP_THX;
 const a_op_info *oi;
 dSP;

 oi = a_map_fetch(PL_op);

 if (oi->flags & A_HINT_DEREF) {
  if (a_undef(TOPs)) {
   /* We always need to push an empty array to fool the pp_aelem() that comes
    * later. */
   SV *av;
   (void) POPs;
   av = sv_2mortal((SV *) newAV());
   PUSHs(av);
   RETURN;
  }
 }

 return oi->old_pp(aTHX);
}

/* ... pp_rv2hv ............................................................ */

STATIC OP *a_pp_rv2hv_simple(pTHX) {
 dA_MAP_THX;
 const a_op_info *oi;
 dSP;

 oi = a_map_fetch(PL_op);

 if (oi->flags & A_HINT_DEREF) {
  if (a_undef(TOPs))
   RETURN;
 }

 return oi->old_pp(aTHX);
}

STATIC OP *a_pp_rv2hv(pTHX) {
 dA_MAP_THX;
 const a_op_info *oi;
 dSP;

 oi = a_map_fetch(PL_op);

 if (oi->flags & A_HINT_DEREF) {
  if (a_undef(TOPs)) {
   SV *hv;
   (void) POPs;
   hv = sv_2mortal((SV *) newHV());
   PUSHs(hv);
   RETURN;
  }
 }

 return oi->old_pp(aTHX);
}

/* ... pp_deref (aelem,helem,rv2sv,padsv) .................................. */

STATIC OP *a_pp_deref(pTHX) {
 dA_MAP_THX;
 const a_op_info *oi;
 UV flags;
 dSP;

 oi = a_map_fetch(PL_op);

 flags = oi->flags;
 if (flags & A_HINT_DEREF) {
  OP *o;

  o = oi->old_pp(aTHX);

  if (flags & (A_HINT_NOTIFY|A_HINT_STORE)) {
   SPAGAIN;
   if (a_undef(TOPs)) {
    if (flags & A_HINT_STRICT)
     croak("Reference vivification forbidden");
    else if (flags & A_HINT_WARN)
      warn("Reference was vivified");
    else /* A_HINT_STORE */
     croak("Can't vivify reference");
   }
  }

  return o;
 }

 return oi->old_pp(aTHX);
}

/* ... pp_root (exists,delete,keys,values) ................................. */

STATIC OP *a_pp_root_unop(pTHX) {
 dSP;

 if (a_undef(TOPs)) {
  (void) POPs;
  /* Can only be reached by keys or values */
  if (GIMME_V == G_SCALAR) {
   dTARGET;
   PUSHi(0);
  }
  RETURN;
 }

 {
  dA_MAP_THX;
  const a_op_info *oi = a_map_fetch(PL_op);
  return oi->old_pp(aTHX);
 }
}

STATIC OP *a_pp_root_binop(pTHX) {
 dSP;

 if (a_undef(TOPm1s)) {
  (void) POPs;
  (void) POPs;
  if (PL_op->op_type == OP_EXISTS)
   RETPUSHNO;
  else
   RETPUSHUNDEF;
 }

 {
  dA_MAP_THX;
  const a_op_info *oi = a_map_fetch(PL_op);
  return oi->old_pp(aTHX);
 }
}

/* --- Check functions ----------------------------------------------------- */

STATIC void a_recheck_rv2xv(pTHX_ OP *o, OPCODE type, OP *(*new_pp)(pTHX)) {
#define a_recheck_rv2xv(O, T, PP) a_recheck_rv2xv(aTHX_ (O), (T), (PP))

 if (o->op_type == type && o->op_ppaddr != new_pp
                        && cUNOPo->op_first->op_type != OP_GV) {
  dA_MAP_THX;
  const a_op_info *oi = a_map_fetch(o);
  if (oi) {
   a_map_store(o, o->op_ppaddr, oi->next, oi->flags);
   o->op_ppaddr = new_pp;
  }
 }

 return;
}

/* ... ck_pad{any,sv} ...................................................... */

/* Sadly, the padsv OPs we are interested in don't trigger the padsv check
 * function, but are instead manually mutated from a padany. So we store
 * the op entry in the op map in the padany check function, and we set their
 * op_ppaddr member in our peephole optimizer replacement below. */

STATIC OP *(*a_old_ck_padany)(pTHX_ OP *) = 0;

STATIC OP *a_ck_padany(pTHX_ OP *o) {
 UV hint;

 o = a_old_ck_padany(aTHX_ o);

 hint = a_hint();
 if (hint & A_HINT_DO)
  a_map_store_root(o, o->op_ppaddr, hint);
 else
  a_map_delete(o);

 return o;
}

STATIC OP *(*a_old_ck_padsv)(pTHX_ OP *) = 0;

STATIC OP *a_ck_padsv(pTHX_ OP *o) {
 UV hint;

 o = a_old_ck_padsv(aTHX_ o);

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
   if ((hint & A_HINT_DO) && !(hint & A_HINT_STRICT))
    a_recheck_rv2xv(cUNOPo->op_first, OP_RV2AV, a_pp_rv2av);
   break;
  case OP_HELEM:
   old_ck = a_old_ck_helem;
   if ((hint & A_HINT_DO) && !(hint & A_HINT_STRICT))
    a_recheck_rv2xv(cUNOPo->op_first, OP_RV2HV, a_pp_rv2hv_simple);
   break;
  case OP_RV2SV:
   old_ck = a_old_ck_rv2sv;
   break;
 }
 o = old_ck(aTHX_ o);

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
  case OP_RV2HV: old_ck = a_old_ck_rv2hv; new_pp = a_pp_rv2hv_simple; break;
 }
 o = old_ck(aTHX_ o);

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

/* ... ck_xslice (aslice,hslice) ........................................... */

/* I think those are only found at the root, but there's nothing that really
 * prevent them to be inside the expression too. We only need to update the
 * root so that the rest of the expression will see the right context when
 * resolving. That's why we don't replace the ppaddr. */

STATIC OP *(*a_old_ck_aslice)(pTHX_ OP *) = 0;
STATIC OP *(*a_old_ck_hslice)(pTHX_ OP *) = 0;

STATIC OP *a_ck_xslice(pTHX_ OP *o) {
 OP * (*old_ck)(pTHX_ OP *o) = 0;
 UV hint = a_hint();

 switch (o->op_type) {
  case OP_ASLICE:
   old_ck = a_old_ck_aslice;
   break;
  case OP_HSLICE:
   old_ck = a_old_ck_hslice;
   if (hint & A_HINT_DO)
    a_recheck_rv2xv(cUNOPo->op_first->op_sibling, OP_RV2HV, a_pp_rv2hv);
   break;
 }
 o = old_ck(aTHX_ o);

 if (hint & A_HINT_DO) {
  a_map_store_root(o, 0, hint);
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
 o = old_ck(aTHX_ o);

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

/* ... Our peephole optimizer .............................................. */

STATIC peep_t a_old_peep = 0; /* This is actually the rpeep past 5.13.5 */

STATIC void a_peep_rec(pTHX_ OP *o, ptable *seen);

STATIC void a_peep_rec(pTHX_ OP *o, ptable *seen) {
#define a_peep_rec(O) a_peep_rec(aTHX_ (O), seen)
 for (; o; o = o->op_next) {
  dA_MAP_THX;
  const a_op_info *oi = NULL;
  UV flags = 0;

#if !A_HAS_RPEEP
  if (ptable_fetch(seen, o))
   break;
  ptable_seen_store(seen, o, o);
#endif

  switch (o->op_type) {
#if A_HAS_RPEEP
   case OP_NEXTSTATE:
   case OP_DBSTATE:
   case OP_STUB:
    if (ptable_fetch(seen, o))
     return;
    ptable_seen_store(seen, o, o);
    break;
#endif
   case OP_PADSV:
    if (o->op_ppaddr != a_pp_deref) {
     oi = a_map_fetch(o);
     if (oi && (oi->flags & A_HINT_DO)) {
      a_map_store(o, o->op_ppaddr, oi->next, oi->flags);
      o->op_ppaddr = a_pp_deref;
     }
    }
    /* FALLTHROUGH */
   case OP_AELEM:
   case OP_AELEMFAST:
   case OP_HELEM:
   case OP_RV2SV:
    if (o->op_ppaddr != a_pp_deref)
     break;
    oi = a_map_fetch(o);
    if (!oi)
     break;
    flags = oi->flags;
    if (!(flags & A_HINT_DEREF)
        && (flags & A_HINT_DO)
        && (o->op_private & OPpDEREF || flags & A_HINT_ROOT)) {
     /* Decide if the expression must autovivify or not. */
     flags = a_map_resolve(o, oi);
    }
    if (flags & A_HINT_DEREF)
     o->op_private = ((o->op_private & ~OPpDEREF) | OPpLVAL_DEFER);
    else
     o->op_ppaddr  = oi->old_pp;
    break;
   case OP_RV2AV:
   case OP_RV2HV:
    if (   o->op_ppaddr != a_pp_rv2av
        && o->op_ppaddr != a_pp_rv2hv
        && o->op_ppaddr != a_pp_rv2hv_simple)
     break;
    oi = a_map_fetch(o);
    if (!oi)
     break;
    if (!(oi->flags & A_HINT_DEREF))
     o->op_ppaddr  = oi->old_pp;
    break;
#if !A_HAS_RPEEP
   case OP_MAPWHILE:
   case OP_GREPWHILE:
   case OP_AND:
   case OP_OR:
   case OP_ANDASSIGN:
   case OP_ORASSIGN:
   case OP_COND_EXPR:
   case OP_RANGE:
# if A_HAS_PERL(5, 10, 0)
   case OP_ONCE:
   case OP_DOR:
   case OP_DORASSIGN:
# endif
    a_peep_rec(cLOGOPo->op_other);
    break;
   case OP_ENTERLOOP:
   case OP_ENTERITER:
    a_peep_rec(cLOOPo->op_redoop);
    a_peep_rec(cLOOPo->op_nextop);
    a_peep_rec(cLOOPo->op_lastop);
    break;
# if A_HAS_PERL(5, 9, 5)
   case OP_SUBST:
    a_peep_rec(cPMOPo->op_pmstashstartu.op_pmreplstart);
    break;
# else
   case OP_QR:
   case OP_MATCH:
   case OP_SUBST:
    a_peep_rec(cPMOPo->op_pmreplstart);
    break;
# endif
#endif /* !A_HAS_RPEEP */
   default:
    break;
  }
 }
}

STATIC void a_peep(pTHX_ OP *o) {
 dMY_CXT;
 ptable *seen = MY_CXT.seen;

 a_old_peep(aTHX_ o);

 ptable_seen_clear(seen);
 a_peep_rec(o);
 ptable_seen_clear(seen);
}

/* --- Interpreter setup/teardown ------------------------------------------ */

STATIC U32 a_initialized = 0;

STATIC void a_teardown(pTHX_ void *root) {

 if (!a_initialized)
  return;

#if A_MULTIPLICITY
 if (aTHX != root)
  return;
#endif

 {
  dMY_CXT;
# if A_THREADSAFE && A_WORKAROUND_REQUIRE_PROPAGATION
  ptable_hints_free(MY_CXT.tbl);
# endif /* A_THREADSAFE && A_WORKAROUND_REQUIRE_PROPAGATION */
  ptable_seen_free(MY_CXT.seen);
 }

 a_ck_restore(OP_PADANY, &a_old_ck_padany);
 a_ck_restore(OP_PADSV,  &a_old_ck_padsv);

 a_ck_restore(OP_AELEM,  &a_old_ck_aelem);
 a_ck_restore(OP_HELEM,  &a_old_ck_helem);
 a_ck_restore(OP_RV2SV,  &a_old_ck_rv2sv);

 a_ck_restore(OP_RV2AV,  &a_old_ck_rv2av);
 a_ck_restore(OP_RV2HV,  &a_old_ck_rv2hv);

 a_ck_restore(OP_ASLICE, &a_old_ck_aslice);
 a_ck_restore(OP_HSLICE, &a_old_ck_hslice);

 a_ck_restore(OP_EXISTS, &a_old_ck_exists);
 a_ck_restore(OP_DELETE, &a_old_ck_delete);
 a_ck_restore(OP_KEYS,   &a_old_ck_keys);
 a_ck_restore(OP_VALUES, &a_old_ck_values);

#if A_HAS_RPEEP
 PL_rpeepp  = a_old_peep;
#else
 PL_peepp   = a_old_peep;
#endif
 a_old_peep = 0;

 a_initialized = 0;
}

STATIC void a_setup(pTHX) {
#define a_setup() a_setup(aTHX)
 if (a_initialized)
  return;

 {
  MY_CXT_INIT;
# if A_THREADSAFE && A_WORKAROUND_REQUIRE_PROPAGATION
  MY_CXT.tbl   = ptable_new();
  MY_CXT.owner = aTHX;
# endif /* A_THREADSAFE && A_WORKAROUND_REQUIRE_PROPAGATION */
  MY_CXT.seen  = ptable_new();
 }

 a_ck_replace(OP_PADANY, a_ck_padany, &a_old_ck_padany);
 a_ck_replace(OP_PADSV,  a_ck_padsv,  &a_old_ck_padsv);

 a_ck_replace(OP_AELEM,  a_ck_deref,  &a_old_ck_aelem);
 a_ck_replace(OP_HELEM,  a_ck_deref,  &a_old_ck_helem);
 a_ck_replace(OP_RV2SV,  a_ck_deref,  &a_old_ck_rv2sv);

 a_ck_replace(OP_RV2AV,  a_ck_rv2xv,  &a_old_ck_rv2av);
 a_ck_replace(OP_RV2HV,  a_ck_rv2xv,  &a_old_ck_rv2hv);

 a_ck_replace(OP_ASLICE, a_ck_xslice, &a_old_ck_aslice);
 a_ck_replace(OP_HSLICE, a_ck_xslice, &a_old_ck_hslice);

 a_ck_replace(OP_EXISTS, a_ck_root,   &a_old_ck_exists);
 a_ck_replace(OP_DELETE, a_ck_root,   &a_old_ck_delete);
 a_ck_replace(OP_KEYS,   a_ck_root,   &a_old_ck_keys);
 a_ck_replace(OP_VALUES, a_ck_root,   &a_old_ck_values);

#if A_HAS_RPEEP
 a_old_peep = PL_rpeepp;
 PL_rpeepp  = a_peep;
#else
 a_old_peep = PL_peepp;
 PL_peepp   = a_peep;
#endif

#if A_MULTIPLICITY
 call_atexit(a_teardown, aTHX);
#else
 call_atexit(a_teardown, NULL);
#endif

 a_initialized = 1;
}

STATIC U32 a_booted = 0;

/* --- XS ------------------------------------------------------------------ */

MODULE = autovivification      PACKAGE = autovivification

PROTOTYPES: ENABLE

BOOT:
{
 if (!a_booted++) {
  HV *stash;

  a_op_map = ptable_new();
#ifdef USE_ITHREADS
  MUTEX_INIT(&a_op_map_mutex);
#endif

  PERL_HASH(a_hash, __PACKAGE__, __PACKAGE_LEN__);

  stash = gv_stashpvn(__PACKAGE__, __PACKAGE_LEN__, 1);
  newCONSTSUB(stash, "A_HINT_STRICT", newSVuv(A_HINT_STRICT));
  newCONSTSUB(stash, "A_HINT_WARN",   newSVuv(A_HINT_WARN));
  newCONSTSUB(stash, "A_HINT_FETCH",  newSVuv(A_HINT_FETCH));
  newCONSTSUB(stash, "A_HINT_STORE",  newSVuv(A_HINT_STORE));
  newCONSTSUB(stash, "A_HINT_EXISTS", newSVuv(A_HINT_EXISTS));
  newCONSTSUB(stash, "A_HINT_DELETE", newSVuv(A_HINT_DELETE));
  newCONSTSUB(stash, "A_HINT_MASK",   newSVuv(A_HINT_MASK));
  newCONSTSUB(stash, "A_THREADSAFE",  newSVuv(A_THREADSAFE));
  newCONSTSUB(stash, "A_FORKSAFE",    newSVuv(A_FORKSAFE));
 }

 a_setup();
}

#if A_THREADSAFE

void
CLONE(...)
PROTOTYPE: DISABLE
PREINIT:
#if A_WORKAROUND_REQUIRE_PROPAGATION
 ptable *t;
#endif
 ptable *s;
PPCODE:
 {
  dMY_CXT;
#if A_WORKAROUND_REQUIRE_PROPAGATION
  {
   a_ptable_clone_ud ud;

   t = ptable_new();
   a_ptable_clone_ud_init(ud, t, MY_CXT.owner);
   ptable_walk(MY_CXT.tbl, a_ptable_clone, &ud);
   a_ptable_clone_ud_deinit(ud);
  }
#endif
  s = ptable_new();
 }
 {
  MY_CXT_CLONE;
#if A_WORKAROUND_REQUIRE_PROPAGATION
  MY_CXT.tbl   = t;
  MY_CXT.owner = aTHX;
#endif
  MY_CXT.seen  = s;
 }
 reap(3, a_thread_cleanup, NULL);
 XSRETURN(0);

#endif /* A_THREADSAFE */

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
