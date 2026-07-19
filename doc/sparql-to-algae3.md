# Compiling SPARQL to Algae 3

SPARQL's algebra descends from Algae's action vocabulary, so most of the
compilation is transliteration. The interesting parts are (a) the dataset
clause, where compiling *fixes* the meaning of `load`, and (b) the choice of
evaluation mode, where compiling *chooses between* SPARQL's bottom-up algebra
and Algae's top-down reading of the same shapes.

## 1. Prologue and dataset

| SPARQL | Algae 3 |
|---|---|
| `PREFIX p: <i>` | `ns p=<i>` (or `prefix p: <i>`) |
| `BASE <i>` | `base <i>` |
| `FROM <i>` | `load <i>` |
| `FROM NAMED <i>` | `load <i> as <i>` |
| `GRAPH g { P }` | `in g ( P' )` |

Compiling `FROM` to `load` is a semantic commitment, not just a spelling: the
compiled program is only correct if `load` behaves as SPARQL dataset
construction does. Algae 3 therefore specifies `load` as: parse the document,
**merge** it into the working graph — union with blank nodes standardized
apart — with no entailment and no deduplication beyond graph merge. Multiple
`FROM` clauses become successive `load`s whose merges commute. `load … as`
must leave the working graph untouched. (Algae2's `read` was informal on all
of these points; the compilation forces the answers.)

## 2. Query forms and modifiers

| SPARQL | Algae 3 |
|---|---|
| `SELECT [DISTINCT] vars / *` | `collect [distinct] (vars / *)` |
| `ORDER BY`, `LIMIT`, `OFFSET` | `order by`, `limit`, `offset` on the `collect` |
| `ASK` | `test ( P' )` |
| `CONSTRUCT { T } WHERE { P }` | `ask ( P' ) assert ( T' )` — or equivalently `fwrule ask ( P' ) assert ( T' )` |
| `BIND (e AS ?v)` | `let (?v e')` |
| `VALUES (?v…) { (…)… }` | `bindings (?v…) { (…)… }` (`UNDEF` kept) |
| `FILTER (C)` | `{ C' }` — placement is mode-dependent, §3/§4 |
| `OPTIONAL { P }` | `~( P' )` |
| `{ P } UNION { Q }` | `( P' |& Q' )` |
| `MINUS { P }` | `|! ( P' )` |
| `FILTER NOT EXISTS { P }` | `!( P' )` (top-down mode's correlated negation) |

Expressions map operator-for-operator (`=` → `==`, `!=`, `&&`, `||`,
relationals, arithmetic; builtins and extension functions become calls).
Deferred: aggregates/`GROUP BY`, property paths, sub-`SELECT` with its own
modifiers, `DESCRIBE`, `SERVICE`.

## 3. Top-down mode (the Algae-native reading)

Emit `require <http://www.w3.org/ns/algae3#eval-topdown>` and translate
structurally: group braces become parentheses, patterns stay where they are,
filters apply where written with inherited bindings in scope. This is the
"intuitive" reading of the SPARQL surface syntax; for well-designed patterns
it coincides with SPARQL's answers.

## 4. Bottom-up mode (SPARQL-faithful)

Emit `require <http://www.w3.org/ns/algae3#eval-bottomup>` and compile each
SPARQL group `{ … }` so that its isolation from outer bindings — the essence
of bottom-up evaluation — is explicit:

1. **Scope each group.** `{ P }` becomes `scope ( P' ) share (V)` where `V` is
   the set of SPARQL *in-scope* variables of `P`. Joining on shared names is
   exactly SPARQL's compatibility join, so `join`/`leftjoin` over the scoped
   groups reproduces the algebra.
2. **Rename the out-of-scope apart.** Any variable occurring in a group (in a
   filter or expression) that is *not* in-scope there is renamed to a fresh
   variable — `?v` becomes `?v_1`, choosing a suffix that captures nothing.
   The fresh variable is unbound where it is evaluated; a filter over it
   errors, and errors eliminate — precisely SPARQL's verdict for that filter.
   No equality constraint is added, because SPARQL's algebra genuinely does
   *not* correlate such occurrences; making them fresh states that fact
   instead of hiding it.
3. **Absorb immediate OPTIONAL filters.** SPARQL defines
   `OPTIONAL { P FILTER(C) }` as `LeftJoin(…, P, C)` with `C` evaluated over
   the *merged* solution, so outer variables in `C` are visible. Compile it as
   `~( scope ( P' ) share (V) . { C" } )` — the filter sits *outside* the
   scope, at the join, where outer names remain in scope. Only filter
   variables that are in scope at the LeftJoin keep their names; deeper ones
   fall under rule 2. This is the one place SPARQL's spec itself patches
   bottom-up scoping toward the top-down intuition, and the compilation
   preserves the patch.

## 5. The divergence, worked

The canonical discriminating query (a doubly nested `OPTIONAL`, after the
SPARQL specification's own bottom-up discussion):

```sparql
PREFIX : <http://example.org/ns#>
SELECT * FROM <http://example.org/d>
WHERE { :a :p ?v
        OPTIONAL { :b :q ?w
                   OPTIONAL { :c :r ?u FILTER(?v = 1) } } }
```

over data `D = { :a :p 1 . :b :q 9 . :c :r 7 }`.

**Top-down** (`examples/from-sparql-topdown.a3`):

```
ask ( :a :p ?v .
      ~( :b :q ?w .
         ~( :c :r ?u . {?v == 1} ) ) )
```

evaluating with bindings flowing inward:
`{v=1}` → optional matches `{v=1, w=9}` → inner optional matches `?u`,
filter sees the inherited `v=1`, true → **`{v=1, w=9, u=7}`**.

**Bottom-up** (`examples/from-sparql-bottomup.a3`), per §4 — the middle
group's in-scope variables are `{?w, ?u}`, so the inner filter's `?v` is out
of scope there and rule 2 renames it apart:

```
ask ( scope ( :a :p ?v ) share (?v) .
      ~ scope ( :b :q ?w .
                ~ scope ( :c :r ?u . {?v_1 == 1} ) share (?u)
              ) share (?w ?u) )
```

evaluating inside-out: the innermost scope matches `{u=7}` but `?v_1` is
unbound, the filter errors, the result is eliminated → inner scope yields ∅ →
`leftjoin({w=9}, ∅)` = `{w=9}` → `leftjoin({v=1}, {w=9})` =
**`{v=1, w=9}`, `?u` unbound** — SPARQL's answer, differing from top-down
exactly in `?u`.

Note the absorption rule's contrast: had the filter been *immediately* inside
the first `OPTIONAL` — `OPTIONAL { :b :q ?w FILTER(?v = 1) }` — rule 3 keeps
`?v` by name at the `leftjoin`, both modes agree, and no renaming occurs. One
level deeper, the modes part ways, and the compilation makes the parting
visible as a fresh variable rather than as a silent scoping rule.

The parser renders the two compilations with mode-distinct operator names
(`djoin`/`optjoin` vs `join`/`leftjoin`); from `make check`:

```
(ask (djoin (bgpmatch (t :a :p ?v))
            (optjoin (djoin (bgpmatch (t :b :q ?w))
                            (optjoin (djoin (bgpmatch (t :c :r ?u))
                                            (filter (eq ?v 1))))))))

(ask (join (scope (bgpmatch (t :a :p ?v)) (share ?v))
           (leftjoin (scope (join (bgpmatch (t :b :q ?w))
                                  (leftjoin (scope (join (bgpmatch (t :c :r ?u))
                                                         (filter (eq ?v_1 1)))
                                            (share ?u))))
                     (share ?w ?u)))))
```

## 6. Going the other way

Because top-down evaluation is a *dependent* join, a bottom-up engine can host
it: `djoin(P, Q)` is SQL's `LATERAL`, and `optjoin`/`notexists` are their
correlated variants. So the pair of modes is symmetric: Algae 3 with `scope`
emulates SPARQL, and SPARQL engines with lateral join emulate Algae 3 — the
two languages differ in which semantics gets the ergonomic surface syntax.

## 7. Reference implementation

`lib/sparql-to-a3.js` (ES module, synced from the SWObjects port) compiles a
[sparqljs](https://github.com/RubenVerborgh/SPARQL.js) AST to an Algae 3
script in either mode:

```js
import { compileText } from "./lib/sparql-to-a3.js";
const a3 = compileText(rqText, SparqlJs.Parser, baseIRI, { mode: "bottomup" });
```

- **mode "topdown"** (default) is the structural translation of section 3.
- **mode "bottomup"** realizes section 4: every group, UNION branch and
  MINUS operand becomes `scope ( P' ) share (V)` with `V` its SPARQL
  in-scope variables (BGP/BIND/VALUES/GRAPH/subselect projections
  contribute; FILTERs and MINUS right sides do not); group filters join
  after all operands; OPTIONAL-immediate filters are absorbed outside the
  scope at the LeftJoin (rule 3); out-of-scope expression variables are
  renamed apart to fresh `?v_N` (rule 2), collision-checked against every
  variable in the query.

Coverage: SELECT (DISTINCT, ORDER/LIMIT/OFFSET, GROUP BY, HAVING,
aggregates incl. nested-in-expression `group_concat(x, "sep")`), subselects
(scope pipelines sharing their projection), ASK (`test`), CONSTRUCT
(`ask` + `assert`), FROM/FROM NAMED (`load`), GRAPH (`in`), OPTIONAL (`~`),
UNION (`|&`), MINUS (`|!`, bound to the group accumulated so far), FILTER
(`{...}`, NOT EXISTS -> `!`), BIND (`let`), VALUES (`bindings`, UNDEF
kept), `IN` -> `oneof`, and the builtin map of `examples/manifesty.yaml`.
Unsupported constructs throw with a reason: property paths, SERVICE,
DESCRIBE, bare FILTER EXISTS.

Two notes on fidelity:

- Rule 3 is applied literally: `OPTIONAL { P FILTER(C) }` emits
  `~( scope(P') share(V) . {C''} )` even where section 5's worked rendering
  keeps an already-renamed filter inside the scope - the two placements are
  semantically identical once rule 2 has renamed the out-of-scope names.
- `FILTER NOT EXISTS` compiles to `!` in both modes; in bottom-up
  evaluation `!` is Minus, so SPARQL NOT EXISTS's substitution semantics
  are only reproduced by the top-down reading. The compiler emits a comment
  at such sites.

Verification (differential, in the SWObjects checkout): all eight
`examples/*.rq` compile and parse; the seven evaluable ones match
`examples/expected/` in **both** modes - in particular
`nested-optional.rq` compiled bottom-up reproduces SPARQL's
`{v=1, w=9}` (the `from-sparql-bottomup` golden, `?v` renamed `?v_1` at
the absorbed inner LeftJoin) while its top-down compilation yields
`{v=1, w=9, u=7}`; `negation-scoped.rq` matches its per-mode renderings.
`connectives.rq` is excluded as documented non-equivalent (`||`/`|-`
exceed SPARQL).
