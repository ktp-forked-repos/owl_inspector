:- encoding(utf8).

:- module(owl_tracer, [ 
  (#)/1,
  (#)/2,
  '📌'/1,
  '📌'/2,
  '🔬'/2,
  tracer/2,  
  compare_against/2,
  obtain_file/1,
  clean_database/0,
  abc_names/2,
  abc_names_from_term/2,
  assert_name/2
]).

:- use_module(library(clpfd)).
:- use_module(library(error)).
:- use_module(library(when)).
:- use_module(library(http/json_convert)).

:- json_object
  json_variables(names:list(string)),
  json_tracepoint_constraint(
    id:string,
    names:list(string),
    values:list(string),
    domains:list(string),
    domainSizes:list(integer)
  ),
  json_tracepoint_labeling(
    names:list(string),
    values:list(string),
    domains:list(string),
    domainSizes:list(integer)
  ),
  json_compare_against(
    names:list(string),
    possibleValues:list(integer)
  ). 

% JSON conversion
to_json(Json) :-
  bagof(Names, variables(Names), Bag),  
  append(Bag, List),
  prolog_to_json(json_variables(List), Json).

to_json(Json) :-
  tracepoint_constraint(
    Id, Names, Values, Domains, Sizes),
  maplist(term_string, Domains, DomainsString),
  maplist(term_string, Values, ValuesString),
  prolog_to_json(json_tracepoint_constraint(
    Id, Names, ValuesString, DomainsString, Sizes), Json).

to_json(Json) :-
  tracepoint_labeling(Names, Values, Domains, Sizes),
  maplist(term_string, Domains, DomainsString),
  maplist(term_string, Values, ValuesString),
  prolog_to_json(json_tracepoint_labeling(
    Names, ValuesString, DomainsString, Sizes), Json).

to_json(Json) :-
  cmp_against(Names, PossibleValues),
  prolog_to_json(json_compare_against(Names, PossibleValues), Json).

obtain_file(Bag) :-
  bagof(Json, to_json(Json), Bag).

% tracepoint(Name, Value, Domain)
% to_trace(ID, Name)
% constraint(ID, Names)
:- dynamic
  tracepoint_constraint/5,
  tracepoint_labeling/4,
  constraint/2,
  variables/1,
  cmp_against/2.

% Trace Operators
'📌'(Goal) :- #(Goal).
'📌'(Goal, Names) :- #(Goal, Names).
#(Goal) :- #(Goal, _).

'🔬'(Var1, Var2) :- compare_against(Var1, Var2).

#(Goal, Names) :-
  nonvar(Goal),
  tracer(Goal, Names).

% Decide what to trace
% Trace labeling
tracer(Goal, Names) :-
  current_predicate(labeling, Goal), !,
  write("Trace labeling..."),
  trace_labeling(Goal, Names).

% Trace Goal
% Only trace constraint predicates?
tracer(Goal, Names) :-
  current_predicate(_, Goal),
  write("Trace Goal..."),
  trace_constraint(Goal, Names).

trace_constraint(Goal, Names) :-
  term_variables(Goal, Vars),
  var_names(Vars, Names), !,
  call(Goal),
  assert_constraint(Goal, Names, ConstraintID),
  maplist(trace_var, Vars, Doms, Sizes),
  assertz(tracepoint_constraint(
    ConstraintID, Names, Vars, Doms, Sizes)).

assert_constraint(Goal, Names, ConstraintID) :-
  term_string(Goal, ConstraintID),
  ( \+constraint(ConstraintID, _) -> true
  ; permission_error(apply_constraint_to_name, Goal, ConstraintID)
  ),
  assertz(constraint(ConstraintID, Names)).

% For plot against feature
compare_against(Var1, Var2) :-
  possibleValues([Var1, Var2], PossibleValues),
  var_names([Var1, Var2], Names),
  assertz(cmp_against(Names, PossibleValues)).

possibleValues(Vars, PossibleValues) :-
  bagof(Vars, label(Vars), PossibleValues).

% Get Domain
trace_var(Var, Dom, Size) :-
  write("Trace Var..."),
  fd_size(Var, Size),  
  fd_dom(Var, Dom).

attr_unify_hook(Name, Var) :-
  ( nonvar(Var) -> true
  ; get_attr(Var, owl_tracer, NewName), NewName==Name
  ).

var_names(Vars, Names) :-
  ( nonvar(Names) -> assert_names(Vars, Names)
  ; get_names(Vars, Names)
  ).

assert_names(Vars, Names) :-
  assertz(variables(Names)),
  maplist(assert_name, Vars, Names).

assert_name(Var, Name) :-
  % TODO: Throw error when name already assigned
  put_attr(Var, owl_tracer, Name).

get_names([], []).
get_names([Var|T1], [Name|T2]) :-
  ( integer(Var) -> Name = Var
  ; get_attr(Var, owl_tracer, Name)
  % TODO: Throw error when name not found,
  % Error: variables and names given/not given
  ),
  get_names(T1, T2).

trace_labeling(Goal, Names) :-
  term_variables(Goal, Vars),
  var_names(Vars, Names),
  maplist(trace_labeling(Vars, Names), Vars), !,
  call(Goal).

trace_labeling(AllVars, AllNames, Var) :-
  when(ground(Var), assertz_labeling(AllVars, AllNames)).
  
% assert tracepoint
assertz_labeling(AllVars, AllNames) :-
  maplist(trace_var, AllVars, Doms, Sizes),
  assertz(tracepoint_labeling(
    AllNames, AllVars, Doms, Sizes)).

% TODO: fd_var, ground, etc,
% Print when not fd_dom but grounded variable

% Clean database
clean_database :-
  retractall(variables(_)),
  retractall(constraint(_,_)),
  retractall(tracepoint_constraint(_,_,_,_,_,_)),
  retractall(tracepoint_labeling(_,_,_,_)).

% generate variable names
abc_names_from_term(Term, Result) :-
  term_variables(Term, Vars),
  length(Vars, L),
  abc_names(L, Result).

abc_names(Number, Result) :-
  I is ceiling(Number / 26),
  findnsols(I, R, abc_names(R), List),
  append(List, List2),
  take(Number, List2, Result), !.

abc_names(Result) :-
  length(Result, 26), 
  is_+integer(N),
  term_string(N, Postfix),
  generate_abc(Postfix, Result).

generate_abc(Postfix, Result) :-
  char_code("A", ACode),
  char_code("Z", ZCode),
  atom_codes(Postfix, PCode),
  bagof(C, between(ACode, ZCode, C), Bag),
  maplist(postfix_codes(PCode), Bag, Result).

postfix_codes(Postfix, C, String) :-    
  append([[C], Postfix], List),
  atom_codes(String, List).

take(N, List, Result) :- 
  findnsols(N, Ele, member(Ele, List), Result), !.

is_+integer(1).
is_+integer(N) :- is_+integer(X), N is X + 1.

% Quick Tests
test_trace_vars() :-
  clean_database,
  '📌'([A,B,C] ins 0..3, ["A", "B", "C"]),
  '📌'(B #> A),
  '📌'(C #> B),
  compare_against(A, B),
  '📌'(labeling([],[A,B,C])).

test_trace() :-
  '📌'(X in 1..2, ["A"]),
  '📌'(all_distinct([X,Y,Z])).
