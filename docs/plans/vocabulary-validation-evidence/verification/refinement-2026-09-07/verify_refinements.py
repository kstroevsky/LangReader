from pathlib import Path
import json,copy,hashlib,re,subprocess,sys
H=Path(__file__).resolve().parent
P=H.parents[1]/'implementation-plan.md'
G=Path('/Users/a.stroevskaya/.codex/skills/lossless-plan-evolution/scripts/plan_guard.py')
base=json.loads((H/'base.snapshot.json').read_text()); new=json.loads((H/'candidate.snapshot.json').read_text())
bm={s['path']:s for s in base['sections']}; nm={s['path']:s for s in new['sections']}
ledger=json.loads((H/'base-ledger.json').read_text());target=copy.deepcopy(ledger)
info={
'F01':('AMEND',['DIAG-BANK','DIAG-PAIR','AMENDMENTS','ORDER','HANDOFF'],'Distinguish unchanged production A, B1 with identical deterministic theta strata and independent latent-item draws, and B2 with independent randomized/shifted stratified posterior positions and latent-item draws.',['**B1:** use the same deterministic theta strata/posterior positions as production A','**B2:** use independently randomized or shifted stratified posterior positions']),
'F02':('ADD',['DIAG-PAIR','AMENDMENTS','VERIFY','HANDOFF'],'Add fresh development-confirmation seeds/documents between iterative diagnostic development and the frozen release holdout; freeze before access and do not reuse consumed outcomes for iterative design.',['a fresh **development-confirmation** seed/document set','Use this intermediate set before any release-holdout access.']),
'F03':('AMEND',['STUDY-SAMPLE','STUDY-REHEARSAL','STUDY-SAP','AMENDMENTS','VERIFY','HANDOFF'],'Make pretest interference a blocking confirmatory-collection decision resolved by evidence or a design explicitly accounting for interference; allow developmental measurement.',['**Pretest interference is an explicit blocking decision for confirmatory human collection:**']),
'F04':('AMEND',['STUDY-RUBRIC','AMENDMENTS','VERIFY','HANDOFF'],'Freeze confirmatory target-sense/context mapping and scoring rubric before inspecting confirmatory responses/model outcomes, without feasibility exception.',['There is no feasibility exception.']),
'F05':('AMEND',['STUDY-VALUE','AMENDMENTS','ORDER','VERIFY','HANDOFF'],'Separate core human validity from the broader equal-total-preparation-time comparison; only a specific authoritative prerequisite may make the broader comparison block core validity.',['Separate the **core human validity study** from the **broader equal-total-preparation-time product-value comparison**.']),
'F06':('ADD',['STUDY-SAMPLE','STUDY-REHEARSAL','STUDY-SAP','AMENDMENTS','HANDOFF'],'Add sampling-design diagnostics for minimum inclusion probability, maximum design weight, effective sample size and expected selected-card/final-tail support; no numerical thresholds.',['This plan supplies no numerical thresholds, trimming rules or estimator defaults for them.']),
'F07':('AMEND',['SCOPE','AMENDMENTS','ORDER','HANDOFF'],'Record first future milestone scope, direct counterfactual dependencies, exclusions and review checkpoint. Latest user instruction stops current task before code: documentation and handoff only.',['The latest user instruction stops this task before code changes.','A recommendation is not permission to begin that slice.'])}
byid={r['id']:r for r in target['requirements']}
delta={'schema_version':1,'base_sha256':base['sha256'],'scope':'Closed-world seven-item bounded refinement. F01-F05 are the five requested refinements; F06 sampling diagnostics; F07 execution boundary and latest stop-before-code instruction. All unmentioned text/contracts NO_CHANGE.','changes':[]}
for fid,(op,ids,desc,anchors) in info.items():
 paths=[]
 for rid in ids:
  section=byid[rid]['section'][-1]
  path=next(k for k in nm if nm[k]['heading']==section)
  paths.append(path.split(' / '))
 numeric=set(); versioned=set()
 for path in paths:
  k=' / '.join(path)
  numeric.update(set(nm[k]['numeric_tokens'])-set(bm[k]['numeric_tokens']))
  versioned.update(set(nm[k]['versioned_tokens'])-set(bm[k]['versioned_tokens']))
 delta['changes'].append({'feedback_id':fid,'operation':'AMEND','requirement_ids':ids,'payload_source':'User bounded-refinement request; F07 additionally latest user stop-before-code instruction, recorded in feedback.md.','allowed_sections':paths,'required_literals':anchors,'forbidden_literals':['where feasible'] if fid=='F04' else [],'allowed_new_numeric_tokens':sorted(numeric),'allowed_new_versioned_tokens':sorted(versioned),'reason':desc,'semantic_operation':op})
 for rid in ids:
  r=byid[rid]
  r['normative_payload'].setdefault('approved_refinements',{})[fid]=desc
  if rid=='SCOPE':r['normative_payload']['current_task']='documentation and implementation handoff only; latest user instruction stops before code'
  if rid=='AMENDMENTS':r['normative_payload']['current_task']='documentation and implementation handoff only; first future milestone stops at checkpoint'
  k=next(k for k in nm if nm[k]['heading']==r['section'][-1])
  for field in ['numeric_tokens','versioned_tokens']:r[field]=nm[k][field]
  r['section_sha256']=nm[k]['sha256']
# Preserve exact structured refinements beyond prose summaries.
byid['DIAG-BANK']['normative_payload']['bank_modes']={'A':'unchanged production 512-world bank','B1':{'theta_positions':'identical deterministic production A strata; preserve stratum weights','latent_item_draws':'independent; explicit replication/weighting if larger bank'},'B2':{'theta_positions':'independently randomized/shifted stratified posterior positions','latent_item_draws':'independent of A and B1','method':'freeze before outcomes'},'invariants':['immutable frozen deck/state','separate theta/draw fingerprints','no selection/stopping/production-report leakage','dimension-specific seed tests']}
byid['DIAG-PAIR']['normative_payload']['streams']=['document','residual','knowledge','response','history drift','A','B1 latent-item draws','B2 posterior positions','B2 latent-item draws','success sampling']
byid['VERIFY']['normative_payload']['final'].insert(2,'fresh development-confirmation after freeze and before release holdout')
byid['DIAG-PAIR']['normative_payload']['data_access_order']=['freely reused diagnostic-development','fresh untouched development-confirmation after candidate/configuration/analysis/decision freeze','unchanged release holdout only after confirmation decision']
byid['DIAG-PAIR']['normative_payload']['confirmation_failure']='retain result; return to development; consumed confirmation set cannot serve fresh confirmation for redesigned candidate'
byid['STUDY-SAMPLE']['normative_payload']['pretest_confirmation_gate']={'blocking':True,'resolution':['evidence supports selected procedure','reviewed design explicitly accounts for interference'],'developmental_measurement_allowed':True}
byid['STUDY-RUBRIC']['normative_payload']['confirmatory_freeze']={'artifacts':['target-sense/context mapping','scoring rubric'],'before':['inspection of confirmatory responses','inspection of confirmatory model outcomes'],'feasibility_exception':False}
byid['STUDY-VALUE']['normative_payload']['completion_roles']={'core':['item calibration','deck validity','realized coverage','burden','warm non-inferiority'],'broader':'equal-total-preparation-time product-value comparison','broader_blocks_core':'only when an identified authoritative requirement makes it a release prerequisite'}
for rid in ['STUDY-SAMPLE','STUDY-REHEARSAL','STUDY-SAP']:
 byid[rid]['normative_payload']['sampling_design_diagnostics']={'metrics':['minimum inclusion probability','maximum design weight','effective sample size','expected selected-card support','expected final-tail support'],'definitions':'declare frame, weighting, ESS definition and grouping; unequal-weight ESS is not independent cluster support','numerical_thresholds':'none introduced; eventual SAP/design freeze'}
byid['ORDER']['normative_payload']['first_future_milestone']={'include':['failed-deck forensic records','exact occurrence-mass conservation','A/B1/B2 frozen-deck evaluation','RNG/reproducibility controls','fixed-bank oracles','small-enumeration oracles','natural/fixed-budget/common-replay infrastructure only as direct dependency'],'exclude':['study-data schema changes','production selector changes','warm-production changes','POS policy changes','calibration slots','release-holdout tuning'],'checkpoint':['changed files','mathematical/statistical invariants','production outputs unchanged with diagnostics off','deterministic/reproducibility tests','narrow results','diagnostic overhead','design issues','longitudinal-warm recommendation'],'stop_for_review':True,'current_task':'documentation only; no implementation code'}
for r in target['requirements']:
 if r['id']=='VERIFY':
  # Existing anchor is retained verbatim within the amended acceptance step.
  assert all(a in P.read_text() for a in r['anchors'])
(H/'target-ledger.json').write_text(json.dumps(target,indent=2,ensure_ascii=False)+'\n')
(H/'delta.json').write_text(json.dumps(delta,indent=2,ensure_ascii=False)+'\n')
subprocess.run([sys.executable,str(G),'verify',str(H/'base-plan.md'),str(P),'--delta',str(H/'delta.json'),'--base-ledger',str(H/'base-ledger.json'),'--ledger',str(H/'target-ledger.json'),'--out',str(H/'mechanical-verification.json')],check=True)
print('Changed sections:',[nm[k]['heading'] for k in nm if bm[k]['sha256']!=nm[k]['sha256']])
