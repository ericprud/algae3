# Told bnodes: identifying blank nodes across SPARQL responses

Status: algorithm note accompanying `attach` (spec §3). Reference
implementation: SWObjects `lib/BNodeResolver.{hpp,cpp}`, exercised by
`tests/test_BNodeResolver.cpp`; its `bin/algae3` wires an HTTP SPARQL
protocol client (form-urlencoded POST, `application/sparql-results+xml`)
into `attach`, so scripts run against live endpoints. Endpoint data must
use absolute IRIs — relative ones resolve differently between data load
and query parse, so they cannot survive the protocol round trip.

## 1. Why

`attach` binds an external database as a matchable source. When that source
speaks the SPARQL protocol, top-down (correlated) evaluation is a sequence of
round trips: bindings from one response seed the patterns of the next. That
requires mentioning, in a later query, a term received in an earlier response
— unproblematic for IRIs and literals, but *rejected* for blank nodes in
SPARQL 1.0 ("told bnodes"). A response bnode label is scoped to its one
response; sending it back is meaningless, and a conforming endpoint may
relabel freely between responses.

The same need arises outside Algae: ShEx validation over an endpoint
repeatedly queries node neighborhoods (`?s ?p FOCUS` / `FOCUS ?p ?o`), and
the focus may be a bnode from a previous round.

This note specifies an emulation: each response bnode is associated with a
minimal query **fragment** that uniquely re-identifies it, found by
**instrumenting** the query with extra interrogation round trips.

## 2. Model

- A **fragment** is a set of arcs `(direction, predicate, other)` around a
  *hole* — the bnode being identified. `other` is a ground term or,
  recursively, another identified bnode.
- Each identified bnode gets a stable local **proxy** term, interned by the
  fragment's canonical key (sorted arc serializations, nested fragments in
  braces). Same key across responses ⇒ same proxy: proxies are the
  cross-response identity that labels cannot provide.
- **Mentioning** a proxy in a later query expands it to a fresh variable
  constrained by its fragment's triples.

Identification is *up to structural indistinguishability* through the
discriminating power of the query context plus the row's ground bindings:
truly indistinguishable nodes share one witness proxy, which is
substitutable wherever the same context constrains it.

## 3. The algorithm

`select(query, contextWhere)` executes the query, then for each response
bnode:

1. **Pin.** Build a pin: `contextWhere` with the bnode's variable renamed to
   the hole variable, plus a `FILTER (?v = value)` for each ground co-binding
   in the row. The pin is a query fragment matching the node(s) the response
   row could have meant.
2. **Interrogate** (one round trip): arcs in and out of everything the pin
   matches —

       SELECT ?h ?d ?p ?x WHERE { { PIN } 
         { BIND(1 AS ?d) ?h ?p ?x } UNION { BIND(2 AS ?d) ?x ?p ?h } }

   Labels are consistent *within* one response, so rows partition into
   candidates by `?h`.
3. **Resolve every candidate.** An ambiguous pin (e.g. a subject with two
   anonymous objects under one predicate and no discriminating co-binding)
   still reported that N nodes exist; collapsing to one witness would lose
   the others. Distinct response labels sharing a pin take successive
   candidates — a bijection, correct up to graph automorphism, since the
   labels carried no identity to begin with.
4. **Greedy minimal fragment** per candidate: sort its arcs ground-`other`
   first (recursion is the expensive path), out-arcs before in-arcs; add arcs
   one at a time; after each, run a **uniqueness check**
   (`SELECT ?u WHERE { FRAGMENT }` — exactly one distinct `?u`?). Stop at the
   first unique fragment. A candidate whose arcs exhaust without uniqueness
   is structurally indistinguishable from a sibling; its full fragment is
   still its best identity and interns onto the sibling's proxy.
5. **Recurse through neighbor bnodes.** When an arc's `other` is itself a
   bnode, identify it with the neighbor as the new hole, pinned by: the outer
   pin (hole renamed to a "previous" variable), **narrowed by the arcs
   already accumulated** for the hole, plus the link arc. Within one
   interrogation response: a neighbor label resolves once and is reused
   across arcs; sibling neighbors sharing a link pin draw successive
   candidates from a single recursive resolution (same bijection as step 3,
   and one round trip instead of one per sibling). A depth cap bounds
   pathological nesting.

## 4. The pattern cache

A `RemoteGraphProvider` materializes triple-pattern fetches
(`ensurePattern(s, p, o)`, `NULL` = wildcard, proxies mentioned by fragment)
into a local graph, which the engine then matches normally:

- Algae: bgpmatch faults in each pattern (after substituting the current
  row's bindings) before matching. This is how `attach` over SPARQL executes
  top-down.
- ShEx: `ensureNode(n)` = both neighborhood directions.
- A pattern **subsumed** by an earlier fetch (each slot NULL-or-equal) costs
  nothing: interrogation results answer later neighborhood queries.
- Patterns no RDF triple can match (literal subject/predicate, bnode
  predicate) short-circuit without a round trip.

## 5. Running against a live endpoint

The reference implementation's CLI demo (from SWObjects' `tests/`), with
`bin/sparql` serving the evidence fixtures over the SPARQL protocol:

    ../bin/sparql --serve http://127.0.0.1:8098/sparql \
        -d Algae3/data/evidence.ttl \
        -d Algae3/data/evidence-groups.ttl \
        -d Algae3/data/evidence-rules.ttl &
    sed 's|^load .*|attach <http://127.0.0.1:8098/sparql> ep|' \
        Algae3/evidence-dnf.topdown.a3 | awk '!/^attach/ || !seen++' > /tmp/attach.a3
    ../bin/algae3 /tmp/attach.a3

The output is identical to the local run - result rows *and* proof logs -
even though the group memberships crossing the round trips are anonymous
bnodes. The client is plain http (no TLS) and expects
`application/sparql-results+xml` responses to a form-urlencoded POST of
`query=`.

`bin/sparql --shex-endpoint` runs the ShEx side of the same idea:
`--shex-endpoint <URL> --shex-schema <schema.shex> --shex-map <map>`
validates a shape map against the live endpoint instead of an in-memory
graph, fetching and caching node neighborhoods as validation visits them.
Fixed associations (`node@shape`, `node@!shape`, `@START`) and one query
pattern (`{FOCUS <p> _}` / `{_ <p> FOCUS}`) are both supported - the
pattern's FOCUS candidates are resolved with one additional round trip
through the same `BNodeResolver::select`, so a bnode FOCUS is told-bnode-
safe the same way a neighborhood fetch is:

    ../bin/sparql --serve http://127.0.0.1:8099/sparql \
        -d Algae3/data/evidence.ttl -d Algae3/data/evidence-groups.ttl
    ../bin/sparql --shex-endpoint http://127.0.0.1:8099/sparql \
        --shex-schema schema.shex \
        --shex-map '{FOCUS ex:member _}@<GroupShape>'

(lib/ShExShapeMap.hpp abstracts triple-pattern matching behind a
`PatternMatcher` interface for this - `LocalPatternMatcher` is the
pre-existing in-memory behavior manifests use; the CLI's
`RemotePatternMatcher` is the endpoint-backed one.)

## 6. Guarantees and limits

Guaranteed: a proxy's mention re-queries to exactly one node; proxies are
stable across arbitrarily relabeled responses; ambiguous pins preserve
cardinality via the candidate bijection. (The reference implementation tests
against a client that freshly relabels every response, so nothing can work
by label luck.)

Deferred / known limits:

- bnodes emerging from **grouped aggregates** (no graph neighborhood to
  interrogate); acceptable while queries do not join bnodes across an
  aggregation boundary.
- correlation of **bnode–bnode co-bindings** across response columns is kept
  only up to fragment identity (ground co-bindings pin; bnode co-bindings do
  not).
- exotic shared-neighbor asymmetries can pair a label with an automorphic
  sibling's fragment; the uniqueness check still guarantees a one-node
  witness.
