/* Algae3Parser.y - bison grammar for Algae 3
 *
 * Repetition/optionality rules follow the yacker expansion conventions used by
 * the SWObjects parser family (SPARQLParser.ypp, TurtleParser.ypp, ...):
 *   X* becomes  _QX_E_Star:  | _QX_E_Star X ;
 *   X? becomes  _QX_E_Opt:   | X ;
 *   X+ becomes  _QX_E_Plus:  X | _QX_E_Plus X ;
 *   ( A B )*    becomes _Q_O_QA_E_S_QB_E_C_E_Star over _O_QA_E_S_QB_E_C: A B ;
 * with GT_ prefixes for punctuation terminals and IT_ for keyword terminals.
 *
 * The parser emits the query as an S-expression over the Algae 3 action
 * algebra.  The evaluation mode - selected by
 *   require <http://www.w3.org/ns/algae3#eval-topdown>   (default)
 *   require <http://www.w3.org/ns/algae3#eval-bottomup>
 * - decides the operator names emitted for the pattern connectives:
 *
 *   surface        top-down          bottom-up
 *   P . Q          djoin             join
 *   ~P             optjoin           leftjoin
 *   !P             notexists         minus
 *   P || Q         orelse            orelse
 *   P |& Q         union             union
 *   P |- Q         munion            munion
 *   P |! Q         diff              diff
 */

%{
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

extern int algae3lex(void);
extern int algae3lineno;
extern FILE *algae3in;
void algae3error(const char *msg);

struct Po { char *v; char *o; char *c; struct Po *nxt; };

static char *fmt(const char *f, ...) {
    va_list ap; char *s;
    va_start(ap, f);
    if (vasprintf(&s, f, ap) < 0) { perror("vasprintf"); exit(2); }
    va_end(ap);
    return s;
}

/* evaluation mode */
enum { EVAL_TOPDOWN, EVAL_BOTTOMUP };
static int evalMode = EVAL_TOPDOWN;
static const char *opConj(void)   { return evalMode == EVAL_TOPDOWN ? "djoin"     : "join"; }
static const char *opOpt(void)    { return evalMode == EVAL_TOPDOWN ? "optjoin"   : "leftjoin"; }
static const char *opNeg(void)    { return evalMode == EVAL_TOPDOWN ? "notexists" : "minus"; }

static void requireFeature(const char *iri) {
    if (strstr(iri, "algae3#eval-bottomup")) evalMode = EVAL_BOTTOMUP;
    else if (strstr(iri, "algae3#eval-topdown")) evalMode = EVAL_TOPDOWN;
    /* other feature IRIs (e.g. ...#rules, ...#proofs) are recorded but have no
     * parse-time effect */
}

/* expand a subject over a property/object list into bgpmatch triples */
static char *declTriples(const char *subj, struct Po *pol) {
    char *acc = strdup("");
    struct Po *p;
    for (p = pol; p; p = p->nxt) {
        char *t = p->c
            ? fmt("(t %s %s %s (where %s))", subj, p->v, p->o, p->c)
            : fmt("(t %s %s %s)", subj, p->v, p->o);
        char *nacc = fmt("%s%s%s", acc, *acc ? " " : "", t);
        free(acc); free(t);
        acc = nacc;
    }
    return fmt("(bgpmatch %s)", acc);
}

static struct Po *poNew(char *o, char *c) {
    struct Po *p = malloc(sizeof *p);
    p->v = NULL; p->o = o; p->c = c; p->nxt = NULL;
    return p;
}
static struct Po *poAppend(struct Po *a, struct Po *b) {
    struct Po *p;
    if (!a) return b;
    for (p = a; p->nxt; p = p->nxt) ;
    p->nxt = b;
    return a;
}
static struct Po *poVerb(char *v, struct Po *objs) {
    struct Po *p;
    for (p = objs; p; p = p->nxt)
        if (!p->v) p->v = v;
    return objs;
}
%}

%name-prefix="algae3"
%error-verbose

%union { char *s; struct Po *po; }

%token IT_ns IT_prefix IT_base IT_require IT_load IT_read IT_as IT_attach
%token IT_ask IT_collect IT_distinct IT_order IT_by IT_asc IT_desc
%token IT_limit IT_offset IT_test IT_assert IT_into IT_fwrule IT_let
%token IT_bindings IT_UNDEF IT_in IT_scope IT_share IT_true IT_false A_KW
%token GT_LPAREN GT_RPAREN GT_LCURLEY GT_RCURLEY GT_LBRACKET GT_RBRACKET
%token GT_DOT GT_SEMI GT_COMMA GT_EQUAL GT_TILDE GT_BANG
%token GT_OR2 GT_UNION GT_MUNION GT_DIFF GT_AND2
%token GT_EQ2 GT_NE GT_LT GT_GT GT_LE GT_GE
%token GT_PLUS GT_MINUS GT_TIMES GT_DIVIDE GT_DTYPE ANON
%token <s> IRIREF PNAME PNAME_NS NAME VAR STRING LANGTAG
%token <s> INTEGER DECIMAL DOUBLE BLANK_LABEL

%type <s> Statement Directive Action NsDecl BaseDecl Require Load Attach Ask
%type <s> Collect Test Assert FwRule Let Bindings
%type <s> _QStatement_E_Star _QDbSpec_E_Opt _QParamList_E_Opt ParamList
%type <s> _QParam_E_Star Param _Q_O_QIT_as_E_S_QGraphName_E_C_E_Opt GraphName
%type <s> GraphPattern Conjunction ConjTail UnaryPattern Decl Scope InGraph
%type <s> CurlyFilter Constraint _QConstraint_E_Opt
%type <s> _QIT_distinct_E_Opt _QVar_E_Plus _QVar_E_Star ProjectionList
%type <s> _QProjection_E_Plus Projection _QByClause_E_Opt Pipeline PipelineHead
%type <s> _QOrderClause_E_Opt OrderClause _QOrderCond_E_Plus OrderCond
%type <s> _QLimitClause_E_Opt LimitClause _QOffsetClause_E_Opt OffsetClause
%type <s> _QIntoClause_E_Opt Term Verb GraphTerm Literal NumericLiteral
%type <s> Expression OrExpr AndExpr RelExpr AddExpr MulExpr UnaryExpr Primary
%type <s> _QArgList_E_Opt ArgList _QRow_E_Star Row _QRowTerm_E_Plus RowTerm
%type <po> PropObjectList VerbObjectList ObjectList ObjectC
%type <po> _Q_O_QGT_SEMI_E_S_QVerbObjectList_E_C_E_Star
%type <po> _O_QGT_SEMI_E_S_QVerbObjectList_E_C
%type <po> _Q_O_QGT_COMMA_E_S_QObjectC_E_C_E_Star _O_QGT_COMMA_E_S_QObjectC_E_C

%%

Query:
    _QStatement_E_Star                  { printf("(algae3%s)\n", $1); }
;

_QStatement_E_Star:
    /* empty */                         { $$ = strdup(""); }
  | _QStatement_E_Star Statement        { $$ = fmt("%s\n  %s", $1, $2); }
;

Statement: Directive { $$ = $1; } | Action { $$ = $1; } ;

Directive:
    NsDecl { $$ = $1; } | BaseDecl { $$ = $1; } | Require { $$ = $1; }
;

/* Algae2 heritage: `ns a=<http://...#>` ; Turtle-style alias: `prefix a: <http://...#>` */
NsDecl:
    IT_ns NAME GT_EQUAL IRIREF          { $$ = fmt("(ns %s %s)", $2, $4); }
  | IT_ns A_KW GT_EQUAL IRIREF          { $$ = fmt("(ns a %s)", $4); }
  | IT_prefix PNAME_NS IRIREF           { $$ = fmt("(ns %s %s)", $2, $3); }
;

BaseDecl: IT_base IRIREF                { $$ = fmt("(base %s)", $2); } ;

Require:
    IT_require IRIREF                   { requireFeature($2); $$ = fmt("(require %s)", $2); }
;

Action:
    Load { $$ = $1; } | Attach { $$ = $1; } | Ask { $$ = $1; }
  | Collect { $$ = $1; } | Test { $$ = $1; } | Assert { $$ = $1; }
  | FwRule { $$ = $1; } | Let { $$ = $1; } | Bindings { $$ = $1; }
  | CurlyFilter { $$ = $1; }
;

/* `load <iri>`           merges into the working graph  (SPARQL FROM)
 * `load <iri> as <g>`    loads as named graph <g>       (SPARQL FROM NAMED)
 * `read` is the deprecated Algae2 spelling of `load`.       */
Load:
    IT_load IRIREF _Q_O_QIT_as_E_S_QGraphName_E_C_E_Opt _QParamList_E_Opt
                                        { $$ = fmt("(load %s%s%s)", $2, $3, $4); }
  | IT_read IRIREF _Q_O_QIT_as_E_S_QGraphName_E_C_E_Opt _QParamList_E_Opt
                                        { $$ = fmt("(load %s%s%s)", $2, $3, $4); }
;

_Q_O_QIT_as_E_S_QGraphName_E_C_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | IT_as GraphName                     { $$ = fmt(" (as %s)", $2); }
;

GraphName: IRIREF { $$ = $1; } | PNAME { $$ = $1; } ;

_QParamList_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | ParamList                           { $$ = fmt(" %s", $1); }
;

ParamList:
    GT_LPAREN _QParam_E_Star GT_RPAREN  { $$ = fmt("(params%s)", $2); }
;

_QParam_E_Star:
    /* empty */                         { $$ = strdup(""); }
  | _QParam_E_Star Param                { $$ = fmt("%s %s", $1, $2); }
;

Param:
    NAME GT_EQUAL Literal               { $$ = fmt("(%s %s)", $1, $3); }
;

Attach:
    IT_attach IRIREF NAME _QParamList_E_Opt
                                        { $$ = fmt("(attach %s %s%s)", $2, $3, $4); }
;

Ask:
    IT_ask _QDbSpec_E_Opt GT_LPAREN GraphPattern GT_RPAREN
                                        { $$ = fmt("(ask%s %s)", $2, $4); }
;

_QDbSpec_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | NAME                                { $$ = fmt(" (db %s)", $1); }
  | IRIREF                              { $$ = fmt(" (db %s)", $1); }
;

Test:
    IT_test GT_LPAREN GraphPattern GT_RPAREN
                                        { $$ = fmt("(test %s)", $3); }
;

Assert:
    IT_assert _QIntoClause_E_Opt GT_LPAREN GraphPattern GT_RPAREN
                                        { $$ = fmt("(assert%s %s)", $2, $4); }
;

_QIntoClause_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | IT_into GraphTerm                   { $$ = fmt(" (into %s)", $2); }
;

FwRule:
    IT_fwrule Ask Assert                { $$ = fmt("(fwrule %s %s)", $2, $3); }
  | IT_fwrule Assert Ask                { $$ = fmt("(fwrule %s %s)", $3, $2); }
;

Let:
    IT_let GT_LPAREN VAR Expression GT_RPAREN
                                        { $$ = fmt("(let %s %s)", $3, $4); }
;

Bindings:
    IT_bindings GT_LPAREN _QVar_E_Plus GT_RPAREN GT_LCURLEY _QRow_E_Star GT_RCURLEY
                                        { $$ = fmt("(bindings (%s) (%s))", $3, $6); }
;

_QRow_E_Star:
    /* empty */                         { $$ = strdup(""); }
  | _QRow_E_Star Row                    { $$ = fmt("%s%s%s", $1, *$1 ? " " : "", $2); }
;

Row:
    GT_LPAREN _QRowTerm_E_Plus GT_RPAREN
                                        { $$ = fmt("(%s)", $2); }
;

_QRowTerm_E_Plus:
    RowTerm                             { $$ = $1; }
  | _QRowTerm_E_Plus RowTerm            { $$ = fmt("%s %s", $1, $2); }
;

RowTerm: Term { $$ = $1; } | IT_UNDEF { $$ = strdup("UNDEF"); } ;

Collect:
    IT_collect _QIT_distinct_E_Opt GT_LPAREN ProjectionList GT_RPAREN
        _QByClause_E_Opt _QOrderClause_E_Opt _QLimitClause_E_Opt _QOffsetClause_E_Opt
                                        { $$ = fmt("(collect (project %s)%s%s%s%s%s)",
                                                   $4, $2, $6, $7, $8, $9); }
;

_QIT_distinct_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | IT_distinct                         { $$ = strdup(" (distinct)"); }
;

ProjectionList:
    _QProjection_E_Plus                 { $$ = $1; }
  | GT_TIMES                            { $$ = strdup("*"); }
;

_QProjection_E_Plus:
    Projection                          { $$ = $1; }
  | _QProjection_E_Plus Projection      { $$ = fmt("%s %s", $1, $2); }
;

Projection:
    VAR                                 { $$ = $1; }
  | GT_LPAREN Expression IT_as VAR GT_RPAREN
                                        { $$ = fmt("(as %s %s)", $2, $4); }
;

/* group the results before aggregate projections apply (SPARQL GROUP BY);
 * a following standalone { expr } filter action plays HAVING. */
_QByClause_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | IT_by GT_LPAREN _QVar_E_Plus GT_RPAREN
                                        { $$ = fmt(" (groupby %s)", $3); }
;

_QVar_E_Plus:
    VAR                                 { $$ = $1; }
  | _QVar_E_Plus VAR                    { $$ = fmt("%s %s", $1, $2); }
;

_QVar_E_Star:
    /* empty */                         { $$ = strdup(""); }
  | _QVar_E_Star VAR                    { $$ = fmt("%s%s%s", $1, *$1 ? " " : "", $2); }
;

_QOrderClause_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | OrderClause                         { $$ = fmt(" %s", $1); }
;

OrderClause:
    IT_order IT_by _QOrderCond_E_Plus   { $$ = fmt("(orderby%s)", $3); }
;

_QOrderCond_E_Plus:
    OrderCond                           { $$ = fmt(" %s", $1); }
  | _QOrderCond_E_Plus OrderCond        { $$ = fmt("%s %s", $1, $2); }
;

OrderCond:
    VAR                                 { $$ = fmt("(asc %s)", $1); }
  | IT_asc GT_LPAREN Expression GT_RPAREN   { $$ = fmt("(asc %s)", $3); }
  | IT_desc GT_LPAREN Expression GT_RPAREN  { $$ = fmt("(desc %s)", $3); }
;

_QLimitClause_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | LimitClause                         { $$ = fmt(" %s", $1); }
;

LimitClause: IT_limit INTEGER           { $$ = fmt("(limit %s)", $2); } ;

_QOffsetClause_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | OffsetClause                        { $$ = fmt(" %s", $1); }
;

OffsetClause: IT_offset INTEGER         { $$ = fmt("(offset %s)", $2); } ;

/* ---- graph patterns ------------------------------------------------- */

GraphPattern:
    Conjunction                         { $$ = $1; }
  | GraphPattern GT_OR2 Conjunction     { $$ = fmt("(orelse %s %s)", $1, $3); }
  | GraphPattern GT_UNION Conjunction   { $$ = fmt("(union %s %s)", $1, $3); }
  | GraphPattern GT_MUNION Conjunction  { $$ = fmt("(munion %s %s)", $1, $3); }
  | GraphPattern GT_DIFF Conjunction    { $$ = fmt("(diff %s %s)", $1, $3); }
;

/* `.` separates; a trailing `.` before `)` or a connective is permitted,
 * as in Algae2's `'(' graphPattern '.'? ')'`. */
Conjunction:
    UnaryPattern ConjTail               { $$ = *$2 ? fmt("(%s %s%s)", opConj(), $1, $2)
                                                   : $1; }
;

ConjTail:
    /* empty */                         { $$ = strdup(""); }
  | GT_DOT                              { $$ = strdup(""); }
  | GT_DOT UnaryPattern ConjTail        { $$ = fmt(" %s%s", $2, $3); }
;

UnaryPattern:
    Decl                                { $$ = $1; }
  | GT_TILDE UnaryPattern               { $$ = fmt("(%s %s)", opOpt(), $2); }
  | GT_BANG UnaryPattern                { $$ = fmt("(%s %s)", opNeg(), $2); }
  | GT_LPAREN GraphPattern GT_RPAREN    { $$ = $2; }
  | InGraph                             { $$ = $1; }
  | Scope                               { $$ = $1; }
  | CurlyFilter                         { $$ = $1; }
  | Bindings                            { $$ = $1; }   /* inline VALUES */
  | Let                                 { $$ = $1; }   /* inline BIND */
;

InGraph:
    IT_in GraphTerm GT_LPAREN GraphPattern GT_RPAREN
                                        { $$ = fmt("(ingraph %s %s)", $2, $4); }
;

/* scope: evaluate a pattern - or a whole sub-pipeline (subquery) - in its own
 * variable scope, exporting only the shared variables.  In bottom-up mode the
 * scope evaluates from the unit result set (SPARQL group/subselect isolation);
 * in top-down mode the enclosing bindings flow in (lateral subquery). */
Scope:
    IT_scope GT_LPAREN GraphPattern GT_RPAREN IT_share GT_LPAREN _QVar_E_Star GT_RPAREN
                                        { $$ = fmt("(scope %s (share %s))", $3, $7); }
  | IT_scope GT_LPAREN Pipeline GT_RPAREN IT_share GT_LPAREN _QVar_E_Star GT_RPAREN
                                        { $$ = fmt("(scope %s (share %s))", $3, $7); }
;

/* A sub-pipeline may not begin with a bare { expr } filter, a bindings or a
 * let (those readings belong to GraphPattern, where they are now pattern
 * elements); any other action may lead, and any action may follow. */
Pipeline:
    PipelineHead                        { $$ = fmt("(pipeline %s)", $1); }
  | Pipeline Action                     { char *inner = strdup($1 + 10);      /* strip "(pipeline " */
                                          inner[strlen(inner)-1] = 0;        /* strip ")" */
                                          $$ = fmt("(pipeline %s %s)", inner, $2);
                                          free(inner); }
;

PipelineHead:
    Load { $$ = $1; } | Ask { $$ = $1; } | Collect { $$ = $1; } | Test { $$ = $1; }
;

CurlyFilter:
    Constraint                          { $$ = fmt("(filter %s)", $1); }
;

Decl:
    Term PropObjectList                 { $$ = declTriples($1, $2); }
;

PropObjectList:
    VerbObjectList _Q_O_QGT_SEMI_E_S_QVerbObjectList_E_C_E_Star
                                        { $$ = poAppend($1, $2); }
;

_Q_O_QGT_SEMI_E_S_QVerbObjectList_E_C_E_Star:
    /* empty */                         { $$ = NULL; }
  | _Q_O_QGT_SEMI_E_S_QVerbObjectList_E_C_E_Star _O_QGT_SEMI_E_S_QVerbObjectList_E_C
                                        { $$ = poAppend($1, $2); }
;

_O_QGT_SEMI_E_S_QVerbObjectList_E_C:
    GT_SEMI VerbObjectList              { $$ = $2; }
;

VerbObjectList:
    Verb ObjectList                     { $$ = poVerb($1, $2); }
;

ObjectList:
    ObjectC _Q_O_QGT_COMMA_E_S_QObjectC_E_C_E_Star
                                        { $$ = poAppend($1, $2); }
;

_Q_O_QGT_COMMA_E_S_QObjectC_E_C_E_Star:
    /* empty */                         { $$ = NULL; }
  | _Q_O_QGT_COMMA_E_S_QObjectC_E_C_E_Star _O_QGT_COMMA_E_S_QObjectC_E_C
                                        { $$ = poAppend($1, $2); }
;

_O_QGT_COMMA_E_S_QObjectC_E_C:
    GT_COMMA ObjectC                    { $$ = $2; }
;

ObjectC:
    Term _QConstraint_E_Opt             { $$ = poNew($1, *$2 ? $2 : NULL); }
;

_QConstraint_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | Constraint                          { $$ = $1; }
;

Constraint:
    GT_LCURLEY Expression GT_RCURLEY    { $$ = $2; }
;

Verb:
    A_KW                                { $$ = strdup("a"); }
  | IRIREF                              { $$ = $1; }
  | PNAME                               { $$ = $1; }
  | VAR                                 { $$ = $1; }
;

GraphTerm: IRIREF { $$ = $1; } | PNAME { $$ = $1; } | VAR { $$ = $1; } ;

Term:
    IRIREF                              { $$ = $1; }
  | PNAME                               { $$ = $1; }
  | VAR                                 { $$ = $1; }
  | BLANK_LABEL                         { $$ = $1; }
  | ANON                                { $$ = strdup("[]"); }
  | Literal                             { $$ = $1; }
;

Literal:
    STRING                              { $$ = $1; }
  | STRING LANGTAG                      { $$ = fmt("%s%s", $1, $2); }
  | STRING GT_DTYPE IRIREF              { $$ = fmt("%s^^%s", $1, $3); }
  | STRING GT_DTYPE PNAME               { $$ = fmt("%s^^%s", $1, $3); }
  | NumericLiteral                      { $$ = $1; }
  | IT_true                             { $$ = strdup("true"); }
  | IT_false                            { $$ = strdup("false"); }
;

NumericLiteral:
    INTEGER { $$ = $1; } | DECIMAL { $$ = $1; } | DOUBLE { $$ = $1; }
;

/* ---- constraint expressions ----------------------------------------- */

Expression: OrExpr { $$ = $1; } ;

OrExpr:
    AndExpr                             { $$ = $1; }
  | OrExpr GT_OR2 AndExpr               { $$ = fmt("(or %s %s)", $1, $3); }
;

AndExpr:
    RelExpr                             { $$ = $1; }
  | AndExpr GT_AND2 RelExpr             { $$ = fmt("(and %s %s)", $1, $3); }
;

RelExpr:
    AddExpr                             { $$ = $1; }
  | AddExpr GT_EQ2 AddExpr              { $$ = fmt("(eq %s %s)", $1, $3); }
  | AddExpr GT_NE AddExpr               { $$ = fmt("(ne %s %s)", $1, $3); }
  | AddExpr GT_LT AddExpr               { $$ = fmt("(lt %s %s)", $1, $3); }
  | AddExpr GT_GT AddExpr               { $$ = fmt("(gt %s %s)", $1, $3); }
  | AddExpr GT_LE AddExpr               { $$ = fmt("(le %s %s)", $1, $3); }
  | AddExpr GT_GE AddExpr               { $$ = fmt("(ge %s %s)", $1, $3); }
;

AddExpr:
    MulExpr                             { $$ = $1; }
  | AddExpr GT_PLUS MulExpr             { $$ = fmt("(add %s %s)", $1, $3); }
  | AddExpr GT_MINUS MulExpr            { $$ = fmt("(sub %s %s)", $1, $3); }
;

MulExpr:
    UnaryExpr                           { $$ = $1; }
  | MulExpr GT_TIMES UnaryExpr          { $$ = fmt("(mul %s %s)", $1, $3); }
  | MulExpr GT_DIVIDE UnaryExpr         { $$ = fmt("(div %s %s)", $1, $3); }
;

UnaryExpr:
    Primary                             { $$ = $1; }
  | GT_BANG UnaryExpr                   { $$ = fmt("(not %s)", $2); }
  | GT_MINUS UnaryExpr                  { $$ = fmt("(neg %s)", $2); }
;

Primary:
    VAR                                 { $$ = $1; }
  | IRIREF                              { $$ = $1; }
  | PNAME GT_LPAREN _QArgList_E_Opt GT_RPAREN
                                        { $$ = fmt("(call %s%s)", $1, $3); }
  | NAME GT_LPAREN _QArgList_E_Opt GT_RPAREN
                                        { $$ = fmt("(call %s%s)", $1, $3); }
  | NAME GT_LPAREN IT_distinct _QArgList_E_Opt GT_RPAREN
                                        { $$ = fmt("(call %s distinct%s)", $1, $4); }
  | PNAME                               { $$ = $1; }
  | Literal                             { $$ = $1; }
  | GT_LPAREN Expression GT_RPAREN      { $$ = $2; }
;

_QArgList_E_Opt:
    /* empty */                         { $$ = strdup(""); }
  | ArgList                             { $$ = fmt(" %s", $1); }
;

ArgList:
    Expression                          { $$ = $1; }
  | ArgList GT_COMMA Expression         { $$ = fmt("%s %s", $1, $3); }
;

%%

void algae3error(const char *msg) {
    fprintf(stderr, "line %d: %s\n", algae3lineno, msg);
}

int main(int argc, char **argv) {
    int i, status = 0;
    if (argc < 2) {
        if (algae3parse()) status = 1;
        return status;
    }
    for (i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "r");
        void algae3restart(FILE *);
        if (!f) { perror(argv[i]); return 2; }
        printf("-- %s\n", argv[i]);
        algae3restart(f);
        algae3lineno = 1;
        evalMode = EVAL_TOPDOWN;
        if (algae3parse()) status = 1;
        fflush(stdout);
        fclose(f);
    }
    return status;
}
