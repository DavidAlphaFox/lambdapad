%%% Copyright 2014 Garrett Smith <g@rre.tt>
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%% 
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%% 
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.

-module(lpad_template).

-behavior(lpad_generator).

-export([render/3, resolve_refs/2]).

-export([handle_generator_spec/2]).

%%%===================================================================
%%% Render
%%%===================================================================

render(Template, Vars, Target) ->
    Compiled = compile_file(Template),
    Rendered = render(Compiled, Vars),
    write_file(Target, Rendered).

compile_file(Template) ->
    Mod = template_module(Template),
    Opts = [{custom_filters_modules, [lpad_template_filters]}],
    handle_compile(erlydtl:compile(Template, Mod, Opts), Mod, Template).

template_module(Template) ->
    list_to_atom(Template).

handle_compile(ok, Mod, _Src) -> Mod;
handle_compile({ok, Mod}, Mod, _Str) -> Mod;
handle_compile({error, Err}, _Mod, Src) ->
    error({template_compile, Src, Err}).

render(Mod, Vars) ->
    handle_render(Mod:render(Vars), Mod).

handle_render({ok, Bin}, _Mod) -> Bin;
handle_render({error, Err}, Mod) ->
    {Src, _} = Mod:source(),
    error({template_render, Src, Err}).

write_file(File, Bin) ->
    ensure_dir(File),
    lpad_event:notify({file_create, File}),
    handle_write_file(file:write_file(File, Bin), File).

ensure_dir(File) ->
    handle_ensure_dir(filelib:ensure_dir(File), File).

handle_ensure_dir(ok, _File) -> ok;
handle_ensure_dir({error, Err}, File) ->
    error({ensure_dir, File, Err}).

handle_write_file(ok, _File) -> ok;
handle_write_file({error, Err}, File) ->
    error({write_file, File, Err}).

%%%===================================================================
%%% Resolve references
%%%===================================================================

resolve_refs(Str, Vars) when is_list(Str) ->
    Compiled = compile_str(Str),
    iolist_to_list(render(Compiled, Vars)).

compile_str(Str) ->
    Template = iolist_to_binary(Str),
    Mod = str_module(Str),
    handle_compile(erlydtl:compile(Template, Mod), Mod, Str).

str_module(Str) ->
    list_to_atom("string-" ++ integer_to_list(erlang:phash2(Str))).

iolist_to_list(Str) ->
    binary_to_list(iolist_to_binary(Str)).

%%%===================================================================
%%% Generator support
%%%===================================================================

handle_generator_spec({Target, {template, Template}}, Data) ->
    AbsTarget = lpad_session:abs_path(Target),
    AbsTemplate = lpad_session:abs_path(Template),
    Generator = fun() -> render(AbsTemplate, Data, AbsTarget) end,
    Sources = [AbsTemplate, '$data'],
    {ok, [{AbsTarget, Sources, Generator}], Data};
handle_generator_spec({Target, {string, Str}}, Data) ->
    AbsTarget = lpad_session:abs_path(Target),
    Value = resolve_refs(Str, Data),
    Generator = fun() -> lpad_file:write_file(AbsTarget, Value) end,
    {ok, [{AbsTarget, ['$data'], Generator}], Data};
handle_generator_spec(_, Data) ->
    {continue, Data}.