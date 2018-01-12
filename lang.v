From iris.program_logic Require Export language ectx_language ectxi_language.
From iris_io.prelude Require Export base.
From iris.algebra Require Export ofe.
From stdpp Require Import gmap.
Require Export Coq.Logic.Classical_Prop.

Module Plang.
  Definition loc := positive.

  Instance loc_dec_eq (l l' : loc) : Decision (l = l') := _.

  Inductive binop := Add | Sub | Eq | Le | Lt.

  Instance binop_dec_eq (op op' : binop) : Decision (op = op').
  Proof. solve_decision. Defined.

  Inductive expr :=
  | Var (x : var)
  | Rec (e : {bind 2 of expr})
  | App (e1 e2 : expr)
  (* Base Types *)
  | Unit
  | Nat (n : nat)
  | Bool (b : bool)
  | BinOp (op : binop) (e1 e2 : expr)
  (* If then else *)
  | If (e0 e1 e2 : expr)
  (* Products *)
  | Pair (e1 e2 : expr)
  | Fst (e : expr)
  | Snd (e : expr)
  (* Sums *)
  | InjL (e : expr)
  | InjR (e : expr)
  | Case (e0 : expr) (e1 : {bind expr}) (e2 : {bind expr})
  (* Recursive Types *)
  | Fold (e : expr)
  | Unfold (e : expr)
  (* Polymorphic Types *)
  | TLam (e : expr)
  | TApp (e : expr)
  (* Concurrency *)
  | Fork (e : expr)
  (* Reference Types *)
  | Loc (l : loc)
  | Alloc (e : expr)
  | Load (e : expr)
  | Store (e1 : expr) (e2 : expr)
  (* Compare and swap used for fine-grained concurrency *)
  | CAS (e0 : expr) (e1 : expr) (e2 : expr)
  (* Instrumenting Prophecies *)
  | Pr (l : loc)
  | Create_Pr A (P : A → Stream expr)
  | Assign_Pr (e1 e2 : expr).

  Instance Ids_expr : Ids expr. derive. Defined.
  Instance Rename_expr : Rename expr. derive. Defined.
  Instance Subst_expr : Subst expr. derive. Defined.
  Instance SubstLemmas_expr : SubstLemmas expr. derive. Qed.

  (* Notation for bool and nat *)
  Notation "#♭ b" := (Bool b) (at level 20).
  Notation "#n n" := (Nat n) (at level 20).

  (* Instance expr_dec_eq (e e' : expr) : Decision (e = e'). *)
  (* Proof. solve_decision. Defined. *)

  Inductive val :=
  | RecV (e : {bind 1 of expr})
  | TLamV (e : {bind 1 of expr})
  | UnitV
  | NatV (n : nat)
  | BoolV (b : bool)
  | PairV (v1 v2 : val)
  | InjLV (v : val)
  | InjRV (v : val)
  | FoldV (v : val)
  | LocV (l : loc)
  | PrV (l : loc).

  (* Notation for bool and nat *)
  Notation "'#♭v' b" := (BoolV b) (at level 20).
  Notation "'#nv' n" := (NatV n) (at level 20).

  Fixpoint binop_eval (op : binop) : nat → nat → val :=
    match op with
    | Add => λ a b, #nv(a + b)
    | Sub => λ a b, #nv(a - b)
    | Eq => λ a b, if (eq_nat_dec a b) then #♭v true else #♭v false
    | Le => λ a b, if (le_dec a b) then #♭v true else #♭v false
    | Lt => λ a b, if (lt_dec a b) then #♭v true else #♭v false
    end.

  (* Instance val_dec_eq (v v' : val) : Decision (v = v'). *)
  (* Proof. solve_decision. Defined. *)

  Instance val_inh : Inhabited val := populate UnitV.

  Fixpoint of_val (v : val) : expr :=
    match v with
    | RecV e => Rec e
    | TLamV e => TLam e
    | UnitV => Unit
    | NatV v => Nat v
    | BoolV v => Bool v
    | PairV v1 v2 => Pair (of_val v1) (of_val v2)
    | InjLV v => InjL (of_val v)
    | InjRV v => InjR (of_val v)
    | FoldV v => Fold (of_val v)
    | LocV l => Loc l
    | PrV l => Pr l
    end.

  Fixpoint to_val (e : expr) : option val :=
    match e with
    | Rec e => Some (RecV e)
    | TLam e => Some (TLamV e)
    | Unit => Some UnitV
    | Nat n => Some (NatV n)
    | Bool b => Some (BoolV b)
    | Pair e1 e2 => v1 ← to_val e1; v2 ← to_val e2; Some (PairV v1 v2)
    | InjL e => InjLV <$> to_val e
    | InjR e => InjRV <$> to_val e
    | Fold e => v ← to_val e; Some (FoldV v)
    | Loc l => Some (LocV l)
    | Pr l => Some (PrV l)
    | _ => None
    end.

  (** Evaluation contexts *)
  Inductive ectx_item :=
  | AppLCtx (e2 : expr)
  | AppRCtx (v1 : val)
  | TAppCtx
  | PairLCtx (e2 : expr)
  | PairRCtx (v1 : val)
  | BinOpLCtx (op : binop) (e2 : expr)
  | BinOpRCtx (op : binop) (v1 : val)
  | FstCtx
  | SndCtx
  | InjLCtx
  | InjRCtx
  | CaseCtx (e1 : {bind expr}) (e2 : {bind expr})
  | IfCtx (e1 : {bind expr}) (e2 : {bind expr})
  | FoldCtx
  | UnfoldCtx
  | AllocCtx
  | LoadCtx
  | StoreLCtx (e2 : expr)
  | StoreRCtx (v1 : val)
  | CasLCtx (e1 : expr)  (e2 : expr)
  | CasMCtx (v0 : val) (e2 : expr)
  | CasRCtx (v0 : val) (v1 : val)
  | Assign_PrLCtx (e2 : expr)
  | Assign_PrRCtx (v1 : val).

  Definition fill_item (Ki : ectx_item) (e : expr) : expr :=
    match Ki with
    | AppLCtx e2 => App e e2
    | AppRCtx v1 => App (of_val v1) e
    | TAppCtx => TApp e
    | PairLCtx e2 => Pair e e2
    | PairRCtx v1 => Pair (of_val v1) e
    | BinOpLCtx op e2 => BinOp op e e2
    | BinOpRCtx op v1 => BinOp op (of_val v1) e
    | FstCtx => Fst e
    | SndCtx => Snd e
    | InjLCtx => InjL e
    | InjRCtx => InjR e
    | CaseCtx e1 e2 => Case e e1 e2
    | IfCtx e1 e2 => If e e1 e2
    | FoldCtx => Fold e
    | UnfoldCtx => Unfold e
    | AllocCtx => Alloc e
    | LoadCtx => Load e
    | StoreLCtx e2 => Store e e2
    | StoreRCtx v1 => Store (of_val v1) e
    | CasLCtx e1 e2 => CAS e e1 e2
    | CasMCtx v0 e2 => CAS (of_val v0) e e2
    | CasRCtx v0 v1 => CAS (of_val v0) (of_val v1) e
    | Assign_PrLCtx e2 => Assign_Pr e e2
    | Assign_PrRCtx v1 => Assign_Pr (of_val v1) e
    end.

  Lemma to_of_val v : to_val (of_val v) = Some v.
  Proof. by induction v; simplify_option_eq. Qed.

  Lemma of_to_val e v : to_val e = Some v → of_val v = e.
  Proof.
    revert v; induction e; intros; simplify_option_eq; auto with f_equal.
  Qed.

  Instance of_val_inj : Inj (=) (=) of_val.
  Proof. by intros ?? Hv; apply (inj Some); rewrite -!to_of_val Hv. Qed.

  Definition BaseProph := Stream val.
  Definition exprProph := Stream expr.
  CoFixpoint proph_to_expr p :=
    {| Shead := of_val (Shead p); Stail := proph_to_expr (Stail p) |}.

  Lemma proph_to_expr_tail p :
    proph_to_expr (Stail p) = Stail (proph_to_expr p).
  Proof. by destruct p. Qed.

  Global Instance proph_to_expr_inj : Inj eq eq proph_to_expr.
  Proof.
    intros x y Heq%eq_Seq. apply Seq_eq.
    revert x y Heq.
    cofix IH => x y Heq.
    rewrite [proph_to_expr x]Stream_unfold in Heq.
    rewrite [proph_to_expr y]Stream_unfold in Heq.
    destruct x as [xh xt]; destruct y as [yh yt]; simpl in *.
    inversion Heq; simpl in *; subst.
    constructor; auto.
    apply of_val_inj; auto.
  Qed.

  Definition Elem {A B: Type} (b : B) (P : A → B) :=
    ∃ x, P x = b.

  Record Proph :=
    { PrS : Stream val;
      PrA : Type;
      PrP : PrA → Stream expr;
      PrPvals : ∀ x, ∃ s, proph_to_expr s = PrP x;
      PrP_ent :
        ∀ n s s', Elem (proph_to_expr s) PrP → Elem (proph_to_expr s') PrP →
                  Elem (proph_to_expr (take_nth_from n s s')) PrP;
      PrSI : Elem (proph_to_expr PrS) PrP
    }.

  Lemma Prohp_eq_simplify p p' (PrA_eq : PrA p = PrA p') :
    PrS p = PrS p' → match PrA_eq in _ = z return z → Stream expr with
                       eq_refl => PrP p end = PrP p' → p = p'.
  Proof.
    intros Hs Ha.
    destruct p as [pS pA pP pPv pPe pPSI].
    destruct p' as [p'S p'A p'P p'Pv p'Pe p'PSI].
    simpl in *.
    destruct PrA_eq; subst.
    f_equal; apply proof_irrelevance.
  Qed.

  Program Definition Proph_tail p :=
    {| PrS := Stail (PrS p); PrA := PrA p; PrP := λ x, Stail (PrP p x) |}.
  Next Obligation.
  Proof.
    intros p x.
    destruct (PrPvals p x) as [s <-].
    exists (Stail s); by rewrite proph_to_expr_tail.
  Qed.
  Next Obligation.
  Proof.
    intros p n s s' [u Hu] [u' Hu'].
    destruct (PrPvals p u) as [w Hw].
    destruct (PrPvals p u') as [w' Hw'].
    destruct (PrP_ent p (S n) w w') as [y Hy].
    { by rewrite Hw; exists u. }
    { by rewrite Hw'; exists u'. }
    exists y. rewrite Hy. simpl.
    rewrite -Hw in Hu; rewrite -Hw' in Hu'.
    apply proph_to_expr_inj in Hu.
    apply proph_to_expr_inj in Hu'.
    by subst.
  Qed.
  Next Obligation.
  Proof.
    intros p.
    destruct (PrSI p) as [y Hy].
    exists y. destruct p as [[h t] ? P ?]; simpl in *.
    destruct (P y); simpl in *.
    apply (f_equal Stail Hy).
  Qed.

  Definition state : Type := (gmap loc val) * (gmap loc Proph).

  Inductive head_step : expr → state → expr → state → list expr → Prop :=
  (* β *)
  | BetaS e1 e2 v2 σ :
      to_val e2 = Some v2 →
      head_step (App (Rec e1) e2) σ e1.[(Rec e1), e2/] σ []
  (* Products *)
  | FstS e1 v1 e2 v2 σ :
      to_val e1 = Some v1 → to_val e2 = Some v2 →
      head_step (Fst (Pair e1 e2)) σ e1 σ []
  | SndS e1 v1 e2 v2 σ :
      to_val e1 = Some v1 → to_val e2 = Some v2 →
      head_step (Snd (Pair e1 e2)) σ e2 σ []
  (* Sums *)
  | CaseLS e0 v0 e1 e2 σ :
      to_val e0 = Some v0 →
      head_step (Case (InjL e0) e1 e2) σ e1.[e0/] σ []
  | CaseRS e0 v0 e1 e2 σ :
      to_val e0 = Some v0 →
      head_step (Case (InjR e0) e1 e2) σ e2.[e0/] σ []
    (* nat bin op *)
  | BinOpS op a b σ :
      head_step (BinOp op (#n a) (#n b)) σ (of_val (binop_eval op a b)) σ []
  (* If then else *)
  | IfFalse e1 e2 σ :
      head_step (If (#♭ false) e1 e2) σ e2 σ []
  | IfTrue e1 e2 σ :
      head_step (If (#♭ true) e1 e2) σ e1 σ []
  (* Recursive Types *)
  | Unfold_Fold e v σ :
      to_val e = Some v →
      head_step (Unfold (Fold e)) σ e σ []
  (* Polymorphic Types *)
  | TBeta e σ :
      head_step (TApp (TLam e)) σ e σ []
  (* Concurrency *)
  | ForkS e σ:
      head_step (Fork e) σ Unit σ [e]
  (* Reference Types *)
  | AllocS e v σ σp l :
     to_val e = Some v → σ !! l = None →
     head_step (Alloc e) (σ, σp) (Loc l) (<[l:=v]>σ, σp) []
  | LoadS l v σ :
     σ.1 !! l = Some v →
     head_step (Load (Loc l)) σ (of_val v) σ []
  | StoreS l e v σ σp :
     to_val e = Some v → is_Some (σ !! l) →
     head_step (Store (Loc l) e) (σ, σp) Unit (<[l:=v]>σ, σp) []
  (* Compare and swap *)
  | CasFailS l e1 v1 e2 v2 vl σ :
     to_val e1 = Some v1 → to_val e2 = Some v2 →
     σ.1 !! l = Some vl → vl ≠ v1 →
     head_step (CAS (Loc l) e1 e2) σ (#♭ false) σ []
  | CasSucS l e1 v1 e2 v2 σ σp :
     to_val e1 = Some v1 → to_val e2 = Some v2 →
     σ !! l = Some v1 →
     head_step (CAS (Loc l) e1 e2) (σ, σp) (#♭ true) (<[l:=v2]>σ, σp) []
  (* Prophecy operational semantics *)
  | Create_PrS A P v
               (H : ∀ x, ∃ s, proph_to_expr s = P x)
               (H' : ∀ n s s',
                   Elem (proph_to_expr s) P → Elem (proph_to_expr s') P →
                   Elem (proph_to_expr (take_nth_from n s s')) P)
               (H'' : Elem (proph_to_expr v) P) σ σp :
      head_step (Create_Pr A P) (σ, σp) (Pr (fresh (dom (gset loc) σp)))
                (σ, <[fresh (dom (gset loc) σp):=
                        {|PrS := v; PrA := A; PrP := P; PrPvals := H; PrP_ent := H'; PrSI := H'' |}]>σp) []
  | AssignSucS l e p σ σp :
     σp !! l = Some p → to_val e = Some (Shead (PrS p)) →
     head_step (Assign_Pr (Pr l) e) (σ, σp) Unit (σ, <[l:=Proph_tail p]>σp) []
  | AssignFailS l e w p z s σ σp :
      σp !! l = Some p → to_val e = Some w →
      PrP p z = s → (Shead s) = e → w ≠ Shead (PrS p) →
      head_step (Assign_Pr (Pr l) e) (σ, σp) (Assign_Pr (Pr l) e) (σ, σp) [].

  (** Basic properties about the language *)
  Lemma fill_item_val Ki e :
    is_Some (to_val (fill_item Ki e)) → is_Some (to_val e).
  Proof. intros [v ?]. destruct Ki; simplify_option_eq; eauto. Qed.

  Instance fill_item_inj Ki : Inj (=) (=) (fill_item Ki).
  Proof. destruct Ki; intros ???; simplify_eq; auto with f_equal. Qed.

  Lemma val_stuck e1 σ1 e2 σ2 ef :
    head_step e1 σ1 e2 σ2 ef → to_val e1 = None.
  Proof. destruct 1; naive_solver. Qed.

  Lemma head_ctx_step_val Ki e σ1 e2 σ2 ef :
    head_step (fill_item Ki e) σ1 e2 σ2 ef → is_Some (to_val e).
  Proof. destruct Ki; inversion_clear 1; simplify_option_eq; eauto. Qed.

  Lemma fill_item_no_val_inj Ki1 Ki2 e1 e2 :
    to_val e1 = None → to_val e2 = None →
    fill_item Ki1 e1 = fill_item Ki2 e2 → Ki1 = Ki2.
  Proof.
    destruct Ki1, Ki2; intros; try discriminate; simplify_eq;
    repeat match goal with
           | H : to_val (of_val _) = None |- _ => by rewrite to_of_val in H
           end; auto.
  Qed.

  Lemma alloc_fresh e v σ σp :
    let l := fresh (dom (gset loc) σ) in
    to_val e = Some v → head_step (Alloc e) (σ, σp) (Loc l) (<[l:=v]>σ, σp) [].
  Proof. by intros; apply AllocS, (not_elem_of_dom (D:=gset loc)), is_fresh. Qed.

  Lemma create_pr
        A P v
        (H : ∀ x, ∃ s, proph_to_expr s = P x)
        (H' : ∀ n s s',
            Elem (proph_to_expr s) P → Elem (proph_to_expr s') P →
            Elem (proph_to_expr (take_nth_from n s s')) P)
        (H'' : Elem (proph_to_expr v) P) σ σp :
    head_step (Create_Pr A P) (σ, σp) (Pr (fresh (dom (gset loc) σp)))
              (σ, <[fresh (dom (gset loc) σp):=
                      ({|PrS := v; PrA := A; PrP := P; PrPvals := H; PrP_ent := H'; PrSI := H'' |}) ]>σp) [].
  Proof. intros; eapply Create_PrS. Qed.

  Lemma val_head_stuck e1 σ1 e2 σ2 efs : head_step e1 σ1 e2 σ2 efs → to_val e1 = None.
  Proof. destruct 1; naive_solver. Qed.

  Lemma lang_mixin : EctxiLanguageMixin of_val to_val fill_item head_step.
  Proof.
    split; apply _ || eauto using to_of_val, of_to_val, val_head_stuck,
           fill_item_val, fill_item_no_val_inj, head_ctx_step_val.
  Qed.

  Canonical Structure stateC := leibnizC state.
  Canonical Structure valC := leibnizC val.
  Canonical Structure exprC := leibnizC expr.
End Plang.

Canonical Structure P_ectxi_lang :=
  EctxiLanguage Plang.lang_mixin.
Canonical Structure P_ectx_lang :=
  EctxLanguageOfEctxi P_ectxi_lang.
Canonical Structure P_lang :=
  LanguageOfEctx P_ectx_lang.

Export Plang.

Hint Extern 20 (PureExec _ _ _) => progress simpl : typeclass_instances.

Hint Extern 5 (IntoVal _ _) => eapply to_of_val : typeclass_instances.
Hint Extern 10 (IntoVal _ _) =>
  rewrite /IntoVal /= ?to_of_val /=; eauto : typeclass_instances.

Hint Extern 5 (AsVal _) => eexists; eapply to_of_val : typeclass_instances.
Hint Extern 10 (AsVal _) =>
  eexists; rewrite /IntoVal /= ?to_of_val /=; eauto : typeclass_instances.

Definition is_atomic (e : expr) : Prop :=
  match e with
  | Alloc e => is_Some (to_val e)
  | Load e =>  is_Some (to_val e)
  | Store e1 e2 => is_Some (to_val e1) ∧ is_Some (to_val e2)
  | CAS e1 e2 e3 => is_Some (to_val e1) ∧ is_Some (to_val e2)
                   ∧ is_Some (to_val e3)
  | _ => False
  end.
Local Hint Resolve language.val_irreducible.
Local Hint Resolve to_of_val.
Local Hint Unfold language.irreducible.
Global Instance is_atomic_correct s e : is_atomic e → Atomic s e.
Proof.
  intros Ha; apply strongly_atomic_atomic,  ectx_language_atomic.
  - destruct 1; simpl in *; try tauto; eauto.
  - intros K e' -> Hval%eq_None_not_Some.
    induction K using rev_ind; first done.
    simpl in Ha; rewrite fill_app in Ha; simpl in Ha.
    destruct Hval. apply (fill_val K e'); simpl in *.
    destruct x; naive_solver.
Qed.

Ltac solve_atomic :=
  apply is_atomic_correct; simpl; repeat split;
    rewrite ?to_of_val; eapply mk_is_Some; fast_done.

Hint Extern 0 (Atomic _ _) => solve_atomic.
Hint Extern 0 (Atomic _ _) => solve_atomic : typeclass_instances.
