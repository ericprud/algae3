# Algae 3

*An action-pipeline query language for RDF, modernizing
[Algae2](https://www.w3.org/2004/05/06-Algae/) (2004) — the language whose
evaluation vocabulary (`bgpmatch`, `join`, …) seeded the semantics section of
the SPARQL specification.*

Status: design sketch with a working parser (`lib/Algae3Parser.y`) that emits
the action algebra described here. Nothing below is normative anywhere.

## 1. Why revisit Algae

Algae predates SPARQL and differs from it in three ways worth preserving:

1. **A query is a pipeline, not a clause structure.** Directives (`load`,
   `ask`, `collect`, `assert`…) execute in document order, each transforming
   the *current result set*. There is no privileged `WHERE`; a script can
   interleave loading, matching, filtering, asserting and reporting.
2. **Results carry proofs.** Each result is a tuple of variable bindings
   paired with the set of asserted triples that support it. SPARQL dropped
   provenance of solutions; Algae 3 keeps it (see §3).
3. **Evaluation is top-down.** Bindings established by earlier patterns flow
   into later ones — the intuitive reading, and the one SPARQL's bottom-up
   algebra famously diverges from in nested-`OPTIONAL`/`FILTER` corner cases.
   Algae 3 makes *both* semantics available and makes the difference precise
   (§6, and `doc/sparql-to-algae3.md`).

What Algae2 lacked was the last twenty years: Turtle's lexical conventions,
named graphs, SPARQL's solution modifiers, and a spelled-out algebra. Algae 3
adds those without disturbing the three properties above.

## 2. Data model

An Algae 3 processor maintains:

- a **dataset**: a *working graph* (Algae2's "working graph", SPARQL's default
  graph) plus zero or more *named graphs*;
- a **result set**: an ordered set of results; each result is a partial
  function from variables to RDF terms plus a *proof set* of supporting
  triples. Execution starts from the **unit result set** — one result with no
  bindings and no proofs. An **empty result set** (no results) is absorbing
  for matching actions.

## 3. Execution model: the action pipeline

Each statement denotes an action `ResultSet → ResultSet` (directives like `ns`
affect only parsing). A query is their composition in document order:

| surface | action | effect |
|---|---|---|
| `ns p=<i>` / `prefix p: <i>` / `base <i>` | — | token expansion only |
| `require <feature>` | — | processor feature / evaluation mode (§6) |
| `load <i>` (alias `read`) | `load` | parse the document at `<i>`, **merge** into the working graph (blank nodes standardized apart) |
| `load <i> as <g>` | `load` | parse into named graph `<g>` |
| `attach <driver> name (…)` | `attach` | bind an external database as a matchable source (Algae2 heritage) |
| `ask (P)` | pattern algebra | replace each result by its extensions through `P` (§4, §5) |
| `test (P)` | `test` | keep the pipeline's result set; expose a boolean: "did `P` match?" (SPARQL `ASK`) |
| `collect [distinct] (var… \| (expr as ?v)…) [by (?g…)] [order by…] [limit n] [offset n]` | `project`, `extend`, `groupby`, `distinct`, `orderby`, `slice` | report; solution modifiers in SPARQL's sense. `by` groups for aggregate projections (`count(distinct ?x)`, `group_concat(?x, sep)`, …); a following standalone `{expr}` action plays HAVING |
| `assert [into g] (T)` | `assert` | for each result, instantiate template `T` and add the triples (SPARQL `CONSTRUCT` when reported; `INSERT` when applied) |
| `fwrule ask(P) assert(T)` | `fwrule` | forward rule: whenever `P` matches, `T` holds (2004/06/20-rules heritage) |
| `let (?v expr)` | `extend` | bind `?v` to the value of `expr` in each result (SPARQL `BIND`) |
| `bindings (?v…) { (…)… }` | `bindings` | join an inline table (SPARQL `VALUES`) |

Proofs: `bgpmatch` adds each matched triple to the extending result's proof
set; `assert` records instantiated triples as both output and proof. The
`|-` connective (§5) merges duplicate binding-tuples while *unioning* their
proofs — Algae2's distinctive "merged union", kept because no SPARQL operator
expresses it.

## 4. Patterns: declarations

A declaration is a subject followed by a Turtle-style predicate/object list
(`;` and `,` abbreviations, `a` for `rdf:type`), each object optionally
carrying a **constraint** in braces:

```
?friend a Rolodex:Friend ;
        Rolodex:age ?age {?age >= 18 && ?age < 24} .
```

A declaration evaluates as Algae2 specified: for each result, substitute its
bindings, search the graph, evaluate the constraints, and emit one extended
result per surviving match. This is the action `bgpmatch` followed by
`filter`s for the attached constraints. A constraint may also stand alone as a
pattern: `{?price < ?threshold}`.

Constraint expressions use Algae2's C-style operators (`==`, `!=`, `&&`,
`||`, arithmetic, relationals) plus function calls (`bound(?x)`,
`regex(?s, "^a")`, `datatype(?x)`, extension functions by IRI or prefixed
name). Filter errors (e.g. comparing an unbound variable) eliminate the
result, as in SPARQL.

## 5. Patterns: combinators

Tightest to loosest; `.` binds tighter than the four connectives, which are
mutually left-associative:

| surface | top-down action | bottom-up action | meaning |
|---|---|---|---|
| `P . Q` | `djoin` | `join` | conjunction |
| `~P` | `optjoin` | `leftjoin` | optional |
| `!P` | `notexists` | `minus` | negation |
| `P \|\| Q` | `orelse` | `orelse` | *shortcut* disjunction: `Q` only where `P` yielded nothing |
| `P \|& Q` | `union` | `union` | union of both sides' results |
| `P \|- Q` | `munion` | `munion` | union, merging duplicate tuples and pooling their proofs |
| `P \|! Q` | `diff` | `diff` | results of `P` not compatible with any of `Q` |
| `( P )` | — | — | grouping; a trailing `.` is allowed before `)` |
| `in g ( P )` | `ingraph` | `ingraph` | match `P` against named graph `g` (SPARQL `GRAPH`); `g` a term or variable |
| `scope ( P ) share (?v…)` | `scope` | `scope` | evaluate `P` — or a whole sub-pipeline (`scope ( ask … collect … by (…) )`, the subquery form) — in its own variable scope, exporting only the shared variables. Bottom-up: evaluates from the unit result set (SPARQL group/subselect isolation). Top-down: the enclosing bindings flow in (lateral subquery) |

`~` and `!` generalize Algae2's term-level markers to whole subpatterns; the
Algae2 spelling `~?s p o` still parses (as `~(decl)`).

`scope` is the bridge to SPARQL's compositional semantics: inside it, the
inherited result set is *not* consulted (evaluation restarts from the unit
result set); on exit, its results join with the surrounding pipeline on the
`share`d variables only. §6 and the companion document show how this one
primitive, plus fresh variables, reproduces bottom-up SPARQL exactly.

## 6. Two evaluation modes

```
require <http://www.w3.org/ns/algae3#eval-topdown>    # default
require <http://www.w3.org/ns/algae3#eval-bottomup>
```

- **Top-down** (Algae native): `eval(R, P . Q) = eval(eval(R, P), Q)`.
  Bindings flow left to right and downward into `~`, `!` and constraints;
  `~P` extends each result by `P` *under that result's bindings* or keeps it
  unchanged; `!P` keeps a result iff `P` has no match under its bindings
  (correlated NOT-EXISTS).
- **Bottom-up** (SPARQL algebra): every group evaluates from the unit result
  set in isolation; `.` is compatibility-join, `~` is `LeftJoin`, `!` is
  `Minus`. A processor with only top-down machinery obtains this mode by the
  `scope`/fresh-variable compilation of the companion document; a processor
  with only bottom-up machinery obtains top-down via dependent (lateral)
  joins.

The two modes agree on conjunctive queries and on well-designed patterns (in
the Pérez–Arenas–Gutierrez sense); they diverge exactly where a variable is
mentioned inside a nested group that neither binds it nor receives it — the
companion document works the canonical divergent example under both modes.

Other feature IRIs: `…#rules` (fwrule), `…#proofs` (proof reporting),
`…#attach` (external databases).

## 7. Relation to Algae2 (inventory)

Kept verbatim: `ns n=<i>`, `read`, `attach`, `require`, `ask`/`collect`,
`.`-conjunction with optional trailing dot, `~`, `!`, `{}` constraints,
`||`/`|&`/`|-`, proofs, `fwrule`/`assert`.

Modernized: Turtle lexical layer (prefixed names, `a`, `;`/`,` lists, typed
and language-tagged literals); `load … as` and `in … ( )` replace the
`%ATTRIB` magic variable; `collect` gains `distinct`/`order by`/`limit`/
`offset`; `let` and `bindings` added; `|!` completes the connective family;
`scope`/`share` added; evaluation modes made explicit.

Deferred: RDF collections `( … )` in term position (collides with pattern
grouping; Algae2 lacked them too), `[ … ]` blank-node property lists,
aggregates, property paths, `DESCRIBE`.

## 8. Grammar and parser

`lib/Algae3Parser.bnf` gives the numbered EBNF; `lib/Algae3Parser.y` +
`lib/Algae3Scanner.l` are a conflict-free LALR(1) bison/flex realization
following the SWObjects yacker conventions (`_QX_E_Star`, `_QX_E_Opt`,
`_Q_O_QGT_SEMI_E_S_QVerbObjectList_E_C_E_Star`, …). The parser prints each
query as an S-expression over the actions of §3–§5, with connective names
chosen by the active evaluation mode — `make check` runs it over
`examples/*.a3`.
