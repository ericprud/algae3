# Algae 3

A modern revision of [Algae2](https://www.w3.org/2004/05/06-Algae/) — the
2004 W3C RDF query language whose action vocabulary (`bgpmatch`, `join`, …)
seeded the semantics section of the SPARQL specification. Algae 3 keeps
Algae's action-pipeline shape, proofs, and top-down evaluation; adds Turtle's
lexical layer, named graphs, SPARQL's solution modifiers, and an explicit
action algebra; and makes both the top-down (Algae-native) and bottom-up
(SPARQL-algebra) semantics selectable per query.

## Layout

```
doc/algae3-spec.md          the language: data model, actions, patterns, modes
doc/sparql-to-algae3.md     compiling SPARQL to Algae 3 (both modes), with the
                            canonical nested-OPTIONAL divergence worked end to end
doc/told-bnodes.md          re-identifying blank nodes across SPARQL responses
                            (the algorithm behind `attach` over the SPARQL protocol)
lib/Algae3Parser.bnf        numbered EBNF (yacker conventions)
lib/Algae3Parser.y          bison grammar, conflict-free LALR(1); expansions use
                            the SWObjects _QX_E_Star / _QX_E_Opt naming
lib/Algae3Scanner.l         flex scanner
examples/*.a3               parseable AND runnable examples (loads reference
                            examples/data/*.ttl; golden results in
                            examples/expected/)
lib/Algae3Parser.ypp        the SWObjects realization: bison-C++ grammar +
lib/Algae3Scanner.lpp       flex scanner building a real AST; the full
                            dual-mode evaluator and debugger live in the
                            SWObjects checkout (lib/Algae3.{hpp,cpp},
                            bin/algae3 --debug)
```

## Build and run

```
make            # bison + flex + cc  ->  bin/algae3
make check      # parse every example, print its action algebra
```

`bin/algae3 file.a3 …` parses each file and prints an S-expression over the
action algebra; pattern connectives are named per the active evaluation mode
(`require <http://www.w3.org/ns/algae3#eval-topdown|eval-bottomup>`):
`djoin`/`optjoin`/`notexists` (top-down) vs `join`/`leftjoin`/`minus`
(bottom-up).

## A taste

```
ns foaf=<http://xmlns.com/foaf/0.1/>
load <http://example.org/rolodex.rdf>

ask (?friend a Rolodex:Friend ;
             Rolodex:age ?age {?age >= 18 && ?age < 24} .
     ~(?friend foaf:mbox ?mbox) .
     !(?friend Rolodex:doNotCall true))
collect distinct (?friend ?mbox) order by ?friend limit 10
```

## Provenance

- Algae2 spec: https://www.w3.org/2004/05/06-Algae/
- Algae HOWTO: https://www.w3.org/1999/02/26-modules/User/Algae-HOWTO.html
- Algae rules: https://www.w3.org/2004/06/20-rules/
- Grammar conventions: the SWObjects parser family (SPARQLParser.ypp etc.)
