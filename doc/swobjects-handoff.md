# Handoff prompt: Algae 3 compiler + debugger REPL in SWObjects

Paste the following to a Claude (Fable) running in `~/checkouts/ericprud/swobjects/`:

---

Algae 3 is a modern revision of Algae2 (the 2004 W3C RDF query language whose
action vocabulary seeded SPARQL's semantics section). Its design, grammar and
a working parse-only reference live in the sibling checkout
`../algae3/` — read these first, in this order:

1. `../algae3/README.md` — orientation, build (`make check` parses 11 examples).
2. `../algae3/doc/algae3-spec.md` — data model (dataset + result sets with
   proofs), the action pipeline, pattern combinators, and the two evaluation
   modes: top-down (Algae-native: `djoin`/`optjoin`/`notexists` are
   *correlated* — bindings flow in, like SQL LATERAL) vs bottom-up (SPARQL
   algebra: `join`/`leftjoin`/`minus` evaluate groups from the unit result
   set), selected per query by
   `require <http://www.w3.org/ns/algae3#eval-topdown|eval-bottomup>`.
3. `../algae3/doc/sparql-to-algae3.md` — the SPARQL compilation, including
   `FROM`→`load`'s forced contract and the fresh-variable/`scope … share`
   machinery for bottom-up fidelity.
4. `../algae3/lib/Algae3Parser.bnf` + `.y` + `Algae3Scanner.l` — conflict-free
   LALR(1), already using this repo's yacker naming conventions
   (`_QX_E_Star`, `_QX_E_Opt`, `_Q_O_QGT_SEMI_E_S_QVerbObjectList_E_C_E_Star`).
5. `../algae3/examples/manifesty.yaml` — the manifest of record: 8 entries
   correlating each `.a3` with its SPARQL `.rq` source, progressing from BGPs
   through correlated negation to grouped aggregation; treat it as the test
   manifest and extend it as examples gain data and expected results.

Your mission, in this repo (SWObjects):

**1. Port the parser to the house style.** `Algae3Parser.ypp` +
`Algae3Scanner.lpp` following `SPARQLParser.ypp`/`SPARQLScanner.lpp`
(bison-C++, yacker rule names, paired `.bnf`), building real SWObjects AST
(`SWObjects.hpp` POS/TableOperation family) rather than the reference
parser's S-expression strings. Wire into CMakeLists and add a
`bin/algae3` driver alongside the existing tools.

**2. Implement the evaluator — both modes.** The pipeline threads a
ResultSet (see `ResultSet.hpp`, `RdfDB.hpp`) through actions; `load` must
follow the contract in sparql-to-algae3.md §1 (merge, bnodes standardized
apart; `as` leaves the working graph untouched). Mode differences to honor:
- top-down: `.`/`~`/`!` are correlated (evaluate the right side once per
  row, bindings substituted in); `scope` inherits the enclosing bindings
  (lateral subquery), `share` limits what flows out.
- bottom-up: connectives are SPARQL Join/LeftJoin/Minus; `scope` evaluates
  from the unit result set (subselect isolation).
- Filter errors eliminate. Proof sets ride along on every result; `|-`
  (munion) merges duplicate tuples and pools proofs.
The `collect … by (…)` grouping with `count(distinct …)`/`group_concat(x,
sep)` aggregates, and pipeline-form subqueries (`scope ( ask … collect …
order by … collect … by (…) )`) are required by the aggregation examples.

**3. Build the debugger REPL** (`bin/algae3 --debug file.a3` or an `a3dbg`
tool): step through a pipeline examining the result set and speculatively
testing matches. Suggested command set:
- `step` / `next` — advance one action (into vs over `scope` pipelines);
  `into` descends into a scope; `where` shows the pipeline position.
- `print [n]` — current result set (first n rows), with per-row proof sets;
  `bindings ?v` — column view; `watch ?v` — break when ?v's binding set
  changes.
- `try ( pattern )` — **speculative match**: evaluate the pattern against
  the current result set under the current mode *without committing*,
  report how many rows would extend / drop, then discard.
- `mode` — show/override the evaluation mode mid-session (re-running the
  remaining pipeline both ways is the killer demo).
- `break <action-ordinal>` / `run` / `reset`.
The debugger's motivating scenario is `manifesty.yaml` entry
`negation-scoped`: step to the negative-membership branch and show *why*
bottom-up `MINUS` removes nothing when `?component` is unbound on its left
(disjoint domains ⇒ vacuous), versus the correlated top-down `!` inheriting
one `bindings` injection. Make that inspection effortless.

**4. Test.** Author small Turtle datasets for each manifest entry (the
examples currently reference placeholder IRIs), add expected results, and
differential-test the two modes: `nested-optional` and `negation-scoped`
have *documented, intended* divergences (see the manifest notes and
sparql-to-algae3.md §5); everything else must agree across modes.

Settled design decisions you should keep (flag, don't silently change):
`oneof(x, …)` stands in for SPARQL `IN` (`in` is the GRAPH keyword);
aggregate separators are plain second arguments; fresh variables use the
`?v_1` suffix convention; deferred features: property paths, collections,
`[ … ]` property lists, DESCRIBE, SERVICE, backward rules. One decision
worth an early sanity check of your own: top-down `scope` inheriting
enclosing bindings (lateral) — it is what makes the rule-engine example's
single injection reach the aggregation layers, but it is newer than the
rest of the design.
