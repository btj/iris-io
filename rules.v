From iris.program_logic Require Export weakestpre.
From iris.program_logic Require Import ectx_lifting.
From iris.base_logic Require Export invariants big_op.
From iris.algebra Require Import auth frac agree gmap.
From iris_io Require Export lang.
From iris.proofmode Require Import tactics.
From iris.base_logic Require Export gen_heap.
Import uPred.
Require Export Coq.Logic.Classical_Prop Coq.Logic.Classical_Pred_Type.

(** The CMRA for the heap of the implementation. This is linked to the
    physical heap. *)
Class heapIG Σ := HeapIG {
  heapI_invG : invG Σ;
  heapI_gen_heapG :> gen_heapG loc val Σ;
  prophI_gen_heapG :> gen_heapG loc (Stream val) Σ;
}.

Instance heapIG_irisG `{heapIG Σ} : irisG P_lang Σ := {
  iris_invG := heapI_invG;
  state_interp := λ σ, ((gen_heap_ctx σ.1) ∗ (gen_heap_ctx σ.2))%I
}.
Global Opaque iris_invG.

Notation "l ↦{ q } v" := (mapsto (L:=loc) (V:=val) l q v)
  (at level 20, q at level 50, format "l  ↦{ q }  v") : uPred_scope.
Notation "l ↦ v" := (mapsto (L:=loc) (V:=val) l 1 v) (at level 20) : uPred_scope.

Program Definition accepts {M} {A : Type} (P : Stream A → Prop) (μ : Stream A)
  : uPred M :=
{|
  uPred_holds n x := ∃ μ', P (prepend_n_from n μ μ')
|}.
Next Obligation.
Proof.
  intros ? ? ? ? n1 n2 ? ? Hn1 _ Hn; simpl in *.
  induction Hn; first done.
  apply IHHn.
  destruct Hn1 as [μ' Hn1].
  exists {| Shead := Snth m μ; Stail := μ'|}.
  simpl in Hn1.
  by rewrite -prepend_n_from_Snth.
Qed.

Lemma accept_accepts {M} {A : Type} (P : Stream A → Prop) (μ : Stream A) :
  P μ → (@accepts M _ P μ)%I.
Proof.
  intros Hμ.
  constructor => n ? _ _; cbv -[prepend_n_from].
  eexists (Nat.iter n Stail μ).
  by rewrite prepen_n_from_same.
Qed.

Global Instance accepts_plain {M} {A} P (μ : Stream A) :
  Plain (@accepts M _ P μ).
Proof.
  by constructor; rewrite /Persistent; unseal.
Qed.

Definition with_head {A : Type} M (a : A) (s : Stream A) : Prop :=
  M {| Shead := a; Stail := s |}.

Lemma accepts_tail {M} {A} P μ :
  (@accepts M A P μ ⊢ ▷ @accepts M A (with_head P (Shead μ)) (Stail μ))%I.
Proof.
  destruct μ as [h t]; rewrite /accepts /=.
  unseal; split => n ? ?.
  intros [μ' Hμ'].
  destruct n; first done; simpl in *.
  exists μ'; done.
Qed.

Lemma accepts_tail' {M} {A} P μ :
  (∃ μ' : Stream A, P μ') →
  (▷ @accepts M A (with_head P (Shead μ)) (Stail μ) ⊢ @accepts M A P μ)%I.
Proof.
  destruct μ as [h t]; rewrite /accepts /=.
  unseal; split => n ? ?.
  destruct n; simpl; auto.
Qed.

Lemma accepts_inh {M} {A} P μ :
  ((@accepts M A P μ) → ∃ μ', ⌜P μ'⌝)%I.
Proof.
  constructor=> n x Hx _; unseal; simpl.
  intros ? ? ? ? ? [μ' Hμ'].
  cbv; eauto.
Qed.

Program Definition maxmatch_pre {Σ} {A : Type}
        (P : (prodC (leibnizC (Stream A → Prop))
                              (prodC (leibnizC (Stream A))
                                     (leibnizC (Stream A)))) -n> iProp Σ) :
           (prodC (leibnizC (Stream A → Prop))
                            (prodC (leibnizC (Stream A))
                                   (leibnizC (Stream A)))) -n> iProp Σ :=
  λne k,
  let (M, k') := k in
  let (μ, m) := k' in
  (((∀ μ', accepts (with_head M (Shead μ)) μ' → False) ∧ accepts M m) ∨
   ((∃ μ', accepts (with_head M (Shead μ)) μ') ∧ ⌜Shead m = Shead μ⌝ ∧
          ▷ P (with_head M (Shead μ), (Stail μ, Stail m))))%I.
Next Obligation.
Proof.
  by intros ? ? P n (M, (μ, m)) (M', (μ', m'))
         [HM%leibniz_equiv [Hμ%leibniz_equiv Hm%leibniz_equiv]]; simpl in *; subst.
Qed.

Global Instance maxmatch_pre_contr {Σ} {A : Type} :
  Contractive (@maxmatch_pre Σ A).
Proof.
  intros n f f' Hf (M, (μ, m)); rewrite /maxmatch_pre /=.
  apply or_ne; auto.
  repeat apply and_ne; auto.
  apply later_contractive; auto.
  destruct n as [|n]; auto; simpl in *.
  by rewrite Hf.
Qed.

Definition maxmatch {Σ} {A : Type} (M : Stream A → Prop) μ μ' :=
  fixpoint (@maxmatch_pre Σ A) (M, (μ, μ')).

Global Instance maxmatch_plain {Σ} {A : Type} (M : Stream A → Prop) μ μ' :
  Plain (@maxmatch Σ _ M μ μ').
Proof.
  unfold Plain; iIntros "".
  iRevert (M μ μ').
  iLöb as "IH". iIntros (M μ μ') "H".
  rewrite /maxmatch {3 4}fixpoint_unfold /=.
  iDestruct "H" as "[[#H1 #H2]|(#H1 & #H2 & H3)]".
  - iLeft; iSplit; iAlways; auto.
  - iRight; repeat iSplitR; try by iAlways.
    iDestruct ("IH" with "H3") as "#IH'".
    by iAlways; iNext.
Qed.

Lemma maxmatch_ex {Σ} {A : Type} :
  (∀ (M : Stream A → Prop) (μ : Stream A),
      (∃ p, accepts M p) → ∃ μ', @maxmatch Σ A M μ μ' ∧ accepts M μ')%I.
Proof.
  iLöb as "IH".
  iIntros (M μ); iDestruct 1 as (p) "#Hp".
  pose proof ({| inhabitant := p |}).
  destruct (classic (∃ μ'', with_head M (Shead μ) μ'')) as [[μ'' Hμ'']|Hne];
    last first.
  - iExists p; iSplit; auto. rewrite /maxmatch {2}fixpoint_unfold /=.
    iLeft; iSplit; auto. iIntros (a) "Ha".
    iDestruct (accepts_inh with "Ha") as %?; done.
  - iSpecialize ("IH" $! (with_head M (Shead μ)) (Stail μ) with "[]").
    { iNext. iExists μ''. by iApply accept_accepts. }
    iDestruct "IH"as (μ') "IH".
    iExists {| Shead := (Shead μ); Stail := μ'|}.
    rewrite /maxmatch fixpoint_unfold /=.
    iDestruct "IH" as "[IH Hμ']".
    iSplit; last first.
    { iApply accepts_tail'; eauto. }
    iRight; repeat iSplit; auto.
    { iExists μ''. iApply accept_accepts; eauto. }
    iDestruct "IH" as "[[IH Hn]|[IHi [IHheq IH]]]".
    + iNext. rewrite {1}fixpoint_unfold /=.
      iLeft; iSplit; auto.
    + iNext. rewrite {2}fixpoint_unfold /=.
      iRight; repeat iSplit; auto.
Qed.

Lemma maxmatch_accepts_head {Σ} {A} M μ μ' :
  (@maxmatch Σ A M μ μ' -∗
            (∃ μ'', accepts (with_head M (Shead μ)) μ'') -∗
            ⌜Shead μ' = Shead μ⌝ ∗
                             ▷ maxmatch (with_head M (Shead μ)) (Stail μ) (Stail μ'))%I.
Proof.
  iIntros "Hmx Hac"; iDestruct "Hac" as (μ'') "Hac".
  rewrite /maxmatch {1}fixpoint_unfold /=.
  iDestruct "Hmx" as "[[Hmx _] | (_ & Hmx1 & Hmx2)]".
  - iExFalso; iApply "Hmx"; auto.
  - iFrame.
Qed.

Definition cpvar `{heapIG Σ} l M μ' : iProp Σ :=
  (∃ μ, (mapsto (L:=loc) (V:=Stream val) l 1 μ) ∧ maxmatch M μ μ')%I.

(* Notation "l ↦ₚ[ M ] μ" := (cpvar l μ M) (at level 20) : uPred_scope. *)

Section lang_rules.
  Context `{heapIG Σ}.
  Implicit Types P Q : iProp Σ.
  Implicit Types Φ : val → iProp Σ.
  Implicit Types σ : state.
  Implicit Types e : expr.
  Implicit Types v w : val.

  Ltac inv_head_step :=
  repeat match goal with
  | _ => progress simplify_map_eq/= (* simplify memory stuff *)
  | H : to_val _ = Some _ |- _ => apply of_to_val in H
  | H : _ = of_val ?v |- _ =>
     is_var v; destruct v; first[discriminate H|injection H as H]
  | H : head_step ?e _ _ _ _ |- _ =>
     try (is_var e; fail 1); (* inversion yields many goals if [e] is a variable
     and can thus better be avoided. *)
     inversion H; subst; clear H
  end.

  Local Hint Extern 0 (atomic _) => solve_atomic.
  Local Hint Extern 0 (head_reducible _ _) => eexists _, _, _; simpl.

  Local Hint Constructors head_step.
  Local Hint Resolve alloc_fresh.
  Local Hint Resolve to_of_val.

  (** Base axioms for core primitives of the language: Stateful reductions. *)
  Lemma wp_alloc E e v :
    IntoVal e v →
    {{{ True }}} Alloc e @ E {{{ l, RET (LocV l); l ↦ v }}}.
  Proof.
    iIntros (<-%of_to_val Φ) "_ HΦ". iApply wp_lift_atomic_head_step_no_fork; auto.
    iIntros ([σ1 σ1p]) "[Hσ Hσp] /= !>"; iSplit.
    { iPureIntro. eexists _, _, _; by apply alloc_fresh. }
    iNext; iIntros (v2 σ2 efs Hstep); inv_head_step.
    iMod (@gen_heap_alloc with "Hσ") as "[Hσ Hl]"; first done.
    iModIntro; iSplit=> //. iFrame. by iApply "HΦ".
  Qed.

  Lemma wp_load E l q v :
  {{{ ▷ l ↦{q} v }}} Load (Loc l) @ E {{{ RET v; l ↦{q} v }}}.
  Proof.
    iIntros (Φ) ">Hl HΦ". iApply wp_lift_atomic_head_step_no_fork; auto.
    iIntros ([σ1 σ1p]) "[Hσ Hσp] !>".
    iDestruct (@gen_heap_valid with "Hσ Hl") as %?.
    iSplit; first by eauto.
    iNext; iIntros (v2 σ2 efs Hstep); inv_head_step.
    iModIntro; iSplit=> //. iFrame. by iApply "HΦ".
  Qed.

  Lemma wp_store E l v' e v :
    IntoVal e v →
    {{{ ▷ l ↦ v' }}} Store (Loc l) e @ E
    {{{ RET UnitV; l ↦ v }}}.
  Proof.
    iIntros (<-%of_to_val Φ) ">Hl HΦ".
    iApply wp_lift_atomic_head_step_no_fork; auto.
    iIntros ([σ1 σ1p]) "[Hσ Hσp] !>".
    iDestruct (@gen_heap_valid with "Hσ Hl") as %?.
    iSplit.
    { iPureIntro. eexists _, _, _; simpl. econstructor; eauto. }
    iNext; iIntros (v2 σ2 efs Hstep); inv_head_step.
    iMod (@gen_heap_update with "Hσ Hl") as "[$ Hl]".
    iModIntro. iSplit=>//. iFrame. by iApply "HΦ".
  Qed.

  Lemma wp_cas_fail E l q v' e1 v1 e2 v2 :
    IntoVal e1 v1 → IntoVal e2 v2 → v' ≠ v1 →
    {{{ ▷ l ↦{q} v' }}} CAS (Loc l) e1 e2 @ E
    {{{ RET (BoolV false); l ↦{q} v' }}}.
  Proof.
    iIntros (<-%of_to_val <-%of_to_val ? Φ) ">Hl HΦ".
    iApply wp_lift_atomic_head_step_no_fork; auto.
    iIntros ([σ1 σ1p]) "[Hσ Hσp] !>".
    iDestruct (@gen_heap_valid with "Hσ Hl") as %?.
    iSplit; first by eauto.
    iNext; iIntros (v2' σ2 efs Hstep); inv_head_step.
    iModIntro; iSplit=> //. iFrame. by iApply "HΦ".
  Qed.

  Lemma wp_cas_suc E l e1 v1 e2 v2 :
    IntoVal e1 v1 → IntoVal e2 v2 →
    {{{ ▷ l ↦ v1 }}} CAS (Loc l) e1 e2 @ E
    {{{ RET (BoolV true); l ↦ v2 }}}.
  Proof.
    iIntros (<-%of_to_val <-%of_to_val Φ) ">Hl HΦ".
    iApply wp_lift_atomic_head_step_no_fork; auto.
    iIntros ([σ1 σ1p]) "[Hσ Hσp] !>".
    iDestruct (@gen_heap_valid with "Hσ Hl") as %?.
    iSplit.
    { iPureIntro. eexists _, _, _; simpl. econstructor; done. }
    iNext; iIntros (v2' σ2 efs Hstep); inv_head_step.
    iMod (@gen_heap_update with "Hσ Hl") as "[$ Hl]".
    iModIntro. iSplit=>//. iFrame. by iApply "HΦ".
  Qed.

  Lemma wp_create_pr E (M : (Stream val) → Prop) :
    (∃ s, M s) →
    {{{ True }}} Create_Pr @ E {{{ l, RET (PrV l);
                                ∃ μ', cpvar l M μ' ∧ accepts M μ'}}}.
  Proof.
    iIntros ([p Hf] Φ) "_ HΦ". iApply wp_lift_atomic_head_step_no_fork; auto.
    iIntros ([σ1 σ1p]) "[Hσ Hσp] /= !>"; iSplit.
    { iPureIntro. eexists _, _, _; simpl. eapply (create_pr (Sconst UnitV)). }
    iNext; iIntros (v2 σ2 efs Hstep). inversion Hstep; simplify_eq.
    iMod (@gen_heap_alloc with "Hσp") as "[Hσp Hl]".
    eapply (not_elem_of_dom (D := gset loc)), is_fresh.
    iModIntro; iSplit=> //. iFrame. iApply "HΦ".
    rewrite /cpvar.
    iDestruct (maxmatch_ex $! M v with "[]") as (μ') "[? ?]"; eauto.
    { iExists p. by iApply accept_accepts. }
  Qed.

  Lemma wp_assign_pr E l e v M μ :
    IntoVal e v →
    {{{ cpvar l M μ ∗ ∃ μ', accepts (with_head M v) μ' }}}
      Assign_Pr (Pr l) e @ E
      {{{ RET UnitV; ⌜v = Shead μ⌝ ∗ cpvar l (with_head M v) (Stail μ)}}}.
  Proof.
    iIntros (<-%of_to_val Φ) "[Hp Hac] HΦ".
    iDestruct "Hp" as (iμ) "[Hp1 Hp2]".
    destruct (classic (v = (Shead iμ))); first simplify_eq.
    - iApply wp_lift_atomic_head_step_no_fork; auto.
      iIntros ([σ1 σ1p]) "[Hσ Hσp] /= !>".
      iDestruct (@gen_heap_valid with "Hσp Hp1") as %?.
      iSplit.
      { iPureIntro. eexists _, _, _; simpl. econstructor; eauto. }
      iDestruct (maxmatch_accepts_head with "Hp2 Hac") as "[% Hmm]".
      iNext; iIntros (v2 σ2 efs Hstep); inv_head_step.
      iMod (@gen_heap_update with "Hσp Hp1") as "[$ Hp1]".
      iModIntro; iSplit=> //. iFrame. iApply "HΦ"; auto.
      iSplit; auto.
      iExists _; iFrame.
    - iClear "HΦ".
      iLöb as "IH".
      iApply wp_lift_head_step; auto.
      iIntros ([σ1 σ1p]) "[Hσ Hσp] /=".
      iDestruct (@gen_heap_valid with "Hσp Hp1") as %?.
      iMod (fupd_intro_mask') as "HM"; last iModIntro; first set_solver.
      iSplit.
      { iPureIntro. eexists _, _, _; simpl. eapply AssignFailS; eauto. }
      iNext; iIntros (v2 σ2 efs Hstep); inv_head_step.
      iMod "HM" as "_". iModIntro.
      iFrame. iSplit; last done.
      iApply ("IH" with "Hp1 Hp2 Hac").
  Qed.

  Lemma wp_rand E Φ :
    ▷ (∀ b, |={E}=> Φ (BoolV b)) ⊢ WP Rand @ E {{ Φ }}.
  Proof.
  rewrite -(wp_lift_head_step Rand) //=; eauto.
  iIntros "HΦ". iIntros ([σ1 σ2]) "[Hσ1 Hσ2]".
  iMod (fupd_intro_mask') as "HM"; last iModIntro; first set_solver.
  iSplit; simpl in *.
  { iPureIntro. do 3 eexists. unshelve econstructor. constructor. }
  iNext. iIntros (e2 σ3 efs Hrd).
    inversion Hrd; subst.
    iMod "HM" as "_"; iModIntro. iFrame.
    iSplit; auto.
      by iApply wp_value_fupd.
  Qed.

  Lemma wp_fork E e Φ :
    ▷ (|={E}=> Φ UnitV) ∗ ▷ WP e {{ _, True }} ⊢ WP Fork e @ E {{ Φ }}.
  Proof.
  rewrite -(wp_lift_pure_det_head_step (Fork e) Unit [e]) //=; eauto.
  - iIntros "[H1 H2]"; iModIntro; iNext; iModIntro; iFrame.
      by iApply wp_value_fupd.
  - intros; inv_head_step; eauto.
  Qed.

  Local Ltac solve_exec_safe := intros; subst; do 3 eexists; econstructor; eauto.
  Local Ltac solve_exec_puredet := simpl; intros; by inv_head_step.
  Local Ltac solve_pure_exec :=
    unfold IntoVal, AsVal in *; subst;
    repeat match goal with H : is_Some _ |- _ => destruct H as [??] end;
    apply det_head_step_pure_exec; [ solve_exec_safe | solve_exec_puredet ].

  Global Instance pure_rec e1 e2 `{!AsVal e2} :
    PureExec True (App (Rec e1) e2) e1.[(Rec e1), e2 /].
  Proof. solve_pure_exec. Qed.

  Global Instance pure_tlam e : PureExec True (TApp (TLam e)) e.
  Proof. solve_pure_exec. Qed.

  Global Instance pure_fold e `{!AsVal e}:
    PureExec True (Unfold (Fold e)) e.
  Proof. solve_pure_exec. Qed.

  Global Instance pure_fst e1 e2 `{!AsVal e1, !AsVal e2} :
    PureExec True (Fst (Pair e1 e2)) e1.
  Proof. solve_pure_exec. Qed.

  Global Instance pure_snd e1 e2 `{!AsVal e1, !AsVal e2} :
    PureExec True (Snd (Pair e1 e2)) e2.
  Proof. solve_pure_exec. Qed.

  Global Instance pure_case_inl e0 e1 e2 `{!AsVal e0}:
    PureExec True (Case (InjL e0) e1 e2) e1.[e0/].
  Proof. solve_pure_exec. Qed.

  Global Instance pure_case_inr e0 e1 e2 `{!AsVal e0}:
    PureExec True (Case (InjR e0) e1 e2) e2.[e0/].
  Proof. solve_pure_exec. Qed.

  Global Instance wp_if_true e1 e2 :
    PureExec True (If (#♭ true) e1 e2) e1.
  Proof. solve_pure_exec. Qed.

  Global Instance wp_if_false e1 e2 :
    PureExec True (If (#♭ false) e1 e2) e2.
  Proof. solve_pure_exec. Qed.

  Global Instance wp_nat_binop op a b :
    PureExec True (BinOp op (#n a) (#n b)) (of_val (binop_eval op a b)).
  Proof. solve_pure_exec. Qed.

End lang_rules.
