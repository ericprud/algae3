/* Algae3Scanner.l - flex scanner for Algae 3
 * Lexical layer aligned with Turtle/SPARQL (IRIREF, PNAME, typed/lang literals),
 * keywords aligned with Algae2 (ns, read, attach, ask, collect, require, fwrule, assert).
 */
%option noyywrap yylineno
%option prefix="algae3"

%{
#include <stdlib.h>
#include <string.h>
#include "Algae3Parser.tab.h"
static char *tok(void) { return strdup(algae3text); }
%}

HEX             [0-9A-Fa-f]
PN_CHARS_BASE   [A-Za-z]
PN_CHARS_U      ({PN_CHARS_BASE}|"_")
PN_CHARS        ({PN_CHARS_U}|[-0-9])
PN_PREFIX       {PN_CHARS_BASE}(({PN_CHARS}|".")*{PN_CHARS})?
PN_LOCAL        ({PN_CHARS_U}|[0-9])(({PN_CHARS}|".")*{PN_CHARS})?

%%

[ \t\r\n]+              { /* skip */ }
"#"[^\n]*               { /* comment */ }

"ns"                    { return IT_ns; }
"prefix"                { return IT_prefix; }
"base"                  { return IT_base; }
"require"               { return IT_require; }
"load"                  { return IT_load; }
"read"                  { return IT_read; }
"as"                    { return IT_as; }
"attach"                { return IT_attach; }
"ask"                   { return IT_ask; }
"collect"               { return IT_collect; }
"distinct"              { return IT_distinct; }
"order"                 { return IT_order; }
"by"                    { return IT_by; }
"asc"                   { return IT_asc; }
"desc"                  { return IT_desc; }
"limit"                 { return IT_limit; }
"offset"                { return IT_offset; }
"test"                  { return IT_test; }
"assert"                { return IT_assert; }
"into"                  { return IT_into; }
"fwrule"                { return IT_fwrule; }
"let"                   { return IT_let; }
"bindings"              { return IT_bindings; }
"UNDEF"                 { return IT_UNDEF; }
"in"                    { return IT_in; }
"scope"                 { return IT_scope; }
"share"                 { return IT_share; }
"true"                  { return IT_true; }
"false"                 { return IT_false; }
"a"                     { return A_KW; }

"<"[^<>\"{}|^`\\ \t\r\n]*">" { algae3lval.s = tok(); return IRIREF; }

{PN_PREFIX}?":"{PN_LOCAL}    { algae3lval.s = tok(); return PNAME; }
{PN_PREFIX}?":"              { algae3lval.s = tok(); return PNAME_NS; }
"_:"{PN_LOCAL}               { algae3lval.s = tok(); return BLANK_LABEL; }
"?"{PN_CHARS_U}({PN_CHARS_U}|[0-9])* { algae3lval.s = tok(); return VAR; }
{PN_PREFIX}                  { algae3lval.s = tok(); return NAME; }

\"([^\"\\\n]|\\.)*\"    { algae3lval.s = tok(); return STRING; }
\'([^\'\\\n]|\\.)*\'    { algae3lval.s = tok(); return STRING; }
"@"[A-Za-z]+(-[A-Za-z0-9]+)* { algae3lval.s = tok(); return LANGTAG; }

[+-]?[0-9]+"."[0-9]*([eE][+-]?[0-9]+)  { algae3lval.s = tok(); return DOUBLE; }
[+-]?[0-9]+[eE][+-]?[0-9]+             { algae3lval.s = tok(); return DOUBLE; }
[+-]?[0-9]+"."[0-9]*                   { algae3lval.s = tok(); return DECIMAL; }
[+-]?[0-9]+                            { algae3lval.s = tok(); return INTEGER; }

"["[ \t\r\n]*"]"        { return ANON; }
"^^"                    { return GT_DTYPE; }
"||"                    { return GT_OR2; }
"|&"                    { return GT_UNION; }
"|-"                    { return GT_MUNION; }
"|!"                    { return GT_DIFF; }
"&&"                    { return GT_AND2; }
"=="                    { return GT_EQ2; }
"!="                    { return GT_NE; }
"<="                    { return GT_LE; }
">="                    { return GT_GE; }
"<"                     { return GT_LT; }
">"                     { return GT_GT; }
"("                     { return GT_LPAREN; }
")"                     { return GT_RPAREN; }
"{"                     { return GT_LCURLEY; }
"}"                     { return GT_RCURLEY; }
"["                     { return GT_LBRACKET; }
"]"                     { return GT_RBRACKET; }
"."                     { return GT_DOT; }
";"                     { return GT_SEMI; }
","                     { return GT_COMMA; }
"="                     { return GT_EQUAL; }
"~"                     { return GT_TILDE; }
"!"                     { return GT_BANG; }
"+"                     { return GT_PLUS; }
"-"                     { return GT_MINUS; }
"*"                     { return GT_TIMES; }
"/"                     { return GT_DIVIDE; }

.                       { fprintf(stderr, "line %d: unexpected character '%s'\n", algae3lineno, algae3text); return algae3text[0]; }

%%
