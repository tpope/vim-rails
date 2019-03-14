" autoload/rails.vim
" Author:       Tim Pope <http://tpo.pe/>

" Install this file as autoload/rails.vim.

if exists('g:autoloaded_rails') || &cp
  finish
endif
let g:autoloaded_rails = '5.4'

" Utility Functions {{{1

let s:app_prototype = {}
let s:file_prototype = {}
let s:buffer_prototype = {}
let s:readable_prototype = {}

function! s:add_methods(namespace, method_names)
  for name in a:method_names
    let s:{a:namespace}_prototype[name] = s:function('s:'.a:namespace.'_'.name)
  endfor
endfunction

function! s:function(name) abort
  return function(substitute(a:name, '^s:', matchstr(expand('<sfile>'),  '.*\zs<SNR>\d\+_'), ''))
endfunction

function! s:sub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! s:startswith(string,prefix)
  return strpart(a:string, 0, strlen(a:prefix)) ==# a:prefix
endfunction

function! s:endswith(string,suffix)
  return strpart(a:string, len(a:string) - len(a:suffix), len(a:suffix)) ==# a:suffix
endfunction

function! s:uniq(list) abort
  let i = 0
  let seen = {}
  while i < len(a:list)
    let key = string(a:list[i])
    if has_key(seen, key)
      call remove(a:list, i)
    else
      let seen[key] = 1
      let i += 1
    endif
  endwhile
  return a:list
endfunction

function! s:getlist(arg, key)
  let value = get(a:arg, a:key, [])
  return type(value) == type([]) ? copy(value) : [value]
endfunction

function! s:split(arg, ...)
  return type(a:arg) == type([]) ? copy(a:arg) : split(a:arg, a:0 ? a:1 : "\n")
endfunction

function! rails#lencmp(i1, i2) abort
  return len(a:i1) - len(a:i2)
endfunction

function! s:escarg(p)
  return s:gsub(a:p,'[ !%#]','\\&')
endfunction

function! s:esccmd(p)
  return s:gsub(a:p,'[!%#]','\\&')
endfunction

function! s:rquote(str)
  if a:str =~ '^[A-Za-z0-9_/.:-]\+$'
    return a:str
  elseif &shell =~? 'cmd'
    return '"'.s:gsub(s:gsub(a:str, '"', '""'), '\%', '"%"').'"'
  else
    return shellescape(a:str)
  endif
endfunction

function! s:fnameescape(file) abort
  if exists('*fnameescape')
    return fnameescape(a:file)
  else
    return escape(a:file," \t\n*?[{`$\\%#'\"|!<")
  endif
endfunction

function! s:dot_relative(path) abort
  let slash = matchstr(a:path, '^\%(\w\:\)\=\zs[\/]')
  if !empty(slash)
    let path = fnamemodify(a:path, ':.')
    if path !=# a:path
      return '.' . slash . path
    endif
  endif
  return a:path
endfunction

function! s:mods(mods) abort
  return s:gsub(a:mods, '[<]mods[>]\s*|^\s', '')
endfunction

function! s:webcat() abort
  if !exists('s:webcat')
    if executable('curl')
      let s:webcat = 'curl'
    elseif executable('wget')
      let s:webcat = 'wget -qO-'
    else
      let s:webcat = ''
    endif
  endif
  return s:webcat
endfunction

function! s:active() abort
  return !empty(get(b:, 'rails_root'))
endfunction

function! s:fcall(fn, path, ...) abort
  let ns = matchstr(a:path, '^\a\a\+\ze:')
  if len(ns) && exists('*' . ns . '#' . a:fn)
    return call(ns . '#' . a:fn, [a:path] + a:000)
  else
    return call(a:fn, [a:path] + a:000)
  endif
endfunction

function! s:filereadable(path) abort
  return s:fcall('filereadable', a:path)
endfunction

function! s:isdirectory(path) abort
  return s:fcall('isdirectory', a:path)
endfunction

function! s:getftime(path) abort
  return s:fcall('getftime', a:path)
endfunction

function! s:simplify(path) abort
  return s:fcall('simplify', a:path)
endfunction

function! s:glob(path) abort
  if v:version >= 704
    return s:fcall('glob', a:path, 0, 1)
  else
    return split(s:fcall('glob', a:path), "\n")
  endif
endfunction

function! s:mkdir_p(path) abort
  if a:path !~# '^\a\a\+:' && !isdirectory(a:path)
    call mkdir(a:path, 'p')
  endif
endfunction

function! s:readfile(path, ...) abort
  if !s:filereadable(a:path)
    return []
  elseif a:0
    return s:fcall('readfile', a:path, '', a:1)
  else
    return s:fcall('readfile', a:path)
  endif
endfunction

function! s:readbuf(path,...) abort
  let nr = bufnr('^'.a:path.'$')
  if nr < 0 && exists('+shellslash') && ! &shellslash
    let nr = bufnr('^'.s:gsub(a:path,'/','\\').'$')
  endif
  if bufloaded(nr)
    return getbufline(nr,1,a:0 ? a:1 : '$')
  elseif a:0
    return s:readfile(a:path, a:1)
  else
    return s:readfile(a:path)
  endif
endfunction

function! s:pop_command()
  if exists("s:command_stack") && len(s:command_stack) > 0
    exe remove(s:command_stack,-1)
  endif
endfunction

function! s:push_chdir(...)
  if !exists("s:command_stack") | let s:command_stack = [] | endif
  if s:active() && (a:0 ? getcwd() !=# rails#app().path() : !s:startswith(getcwd(), rails#app().real()))
    let chdir = exists("*haslocaldir") && haslocaldir() ? "lchdir " : "chdir "
    call add(s:command_stack,chdir.s:escarg(getcwd()))
    exe chdir.s:escarg(rails#app().real())
  else
    call add(s:command_stack,"")
  endif
endfunction

function! s:app_real(...) dict abort
  let pre = substitute(matchstr(self._root, '^\a\a\+\ze:'), '^.', '\u&', '')
  if empty(pre)
    let real = self._root
  elseif exists('*' . pre . 'Real')
    let real = {pre}Real(self._root)
  else
    return ''
  endif
  return join([real]+a:000,'/')
endfunction

function! s:app_path(...) dict dict
  if a:0 && a:1 =~# '\%(^\|^\w*:\)[\/]'
    return a:1
  else
    return join([self._root]+a:000,'/')
  endif
endfunction

function! s:app_spec(...) dict abort
  if a:0 && a:1 =~# '\%(^\|^\w*:\)[\/]'
    return a:1
  else
    return join([self._root]+a:000,'/')
  endif
endfunction

function! s:app_root(...) dict abort
  if a:0 && a:1 =~# '\%(^\|^\w*:\)[\/]'
    return a:1
  else
    return join([self._root]+a:000,'/')
  endif
endfunction

function! s:app_has_path(path) dict abort
  return s:getftime(self.path(a:path)) != -1
endfunction

function! s:app_has_file(file) dict abort
  let file = self.path(a:file)
  return a:file =~# '/$' ? s:isdirectory(file) : s:filereadable(file)
endfunction

function! s:find_file(name, ...) abort
  let path = s:pathsplit(a:0 ? a:1 : &path)
  let index = 1
  let default = ''
  if a:0 > 1 && type(a:2) == type(0)
    let index = a:2
  elseif a:0 > 1 && type(a:2) == type('')
    let default = a:2
  endif
  let results = []
  for glob in path
    for dir in s:glob(glob)
      let dir = substitute(substitute(dir, '[\/]\=$', '/', ''), '^+\ze\a\a\+:', '', '')
      for suf in [''] + (a:name =~# '/$' ? [] : s:pathsplit(get(a:000, 1, [])))
        if s:fcall(a:name =~# '/$' ? 'isdirectory' : 'filereadable', dir . a:name . suf)
          call add(results, dir . a:name . suf)
        endif
        if len(results) == index
          return results[-1]
        endif
      endfor
    endfor
  endfor
  return index == -1 ? results : default
endfunction

function! s:app_find_file(name, ...) dict abort
  if a:0
    let path = map(s:pathsplit(a:1),'self.path(v:val)')
  else
    let path = [self.path()]
  endif
  return s:find_file(a:name, path, a:0 > 1 ? a:2 : '')
endfunction

call s:add_methods('app',['real','path','spec','root','has_path','has_file','find_file'])

" Split a path into a list.
function! s:pathsplit(path) abort
  if type(a:path) == type([]) | return copy(a:path) | endif
  return split(s:gsub(a:path, '\\ ', ' '), ',')
endfunction

" Convert a list to a path.
function! s:pathjoin(...) abort
  let i = 0
  let path = ""
  while i < a:0
    if type(a:000[i]) == type([])
      let path .= "," . escape(join(a:000[i], ','), ' ')
    else
      let path .= "," . a:000[i]
    endif
    let i += 1
  endwhile
  return substitute(path,'^,','','')
endfunction

function! s:readable_end_of(lnum) dict abort
  if a:lnum == 0
    return 0
  endif
  let cline = self.getline(a:lnum)
  let spc = matchstr(cline,'^\s*')
  let endpat = '\<end\>'
  if matchstr(self.getline(a:lnum+1),'^'.spc) && !matchstr(self.getline(a:lnum+1),'^'.spc.endpat) && matchstr(cline,endpat)
    return a:lnum
  endif
  let endl = a:lnum
  while endl <= self.line_count()
    let endl += 1
    if self.getline(endl) =~ '^'.spc.endpat
      return endl
    elseif self.getline(endl) =~ '^=begin\>'
      while self.getline(endl) !~ '^=end\>' && endl <= self.line_count()
        let endl += 1
      endwhile
      let endl += 1
    elseif self.getline(endl) !~ '^'.spc && self.getline(endl) !~ '^\s*\%(#.*\)\=$'
      return 0
    endif
  endwhile
  return 0
endfunction

function! s:endof(lnum)
  return rails#buffer().end_of(a:lnum)
endfunction

function! s:readable_last_opening_line(start,pattern,limit) dict abort
  let line = a:start
  while line > a:limit && self.getline(line) !~ a:pattern
    let line -= 1
  endwhile
  if self.name() =~# '\.\%(rb\|rake\)$'
    let lend = self.end_of(line)
  else
    let lend = -1
  endif
  if line > a:limit && (lend < 0 || lend >= a:start)
    return line
  else
    return -1
  endif
endfunction

function! s:lastopeningline(pattern,limit,start)
  return rails#buffer().last_opening_line(a:start,a:pattern,a:limit)
endfunction

let s:sql_define = substitute(
      \ '\v\c^\s*create %(or replace )=%(table|%(materialized |recursive )=view|%(unique |fulltext )=index|trigger|function|procedure|sequence|extension) %(if not exists )=%(\i+\.)=[`"]=',
      \ ' ', '\\s+', 'g')
function! s:readable_define_pattern() dict abort
  if self.name() =~# '\.yml\%(\.example\|sample\)\=$'
    return '^\%(\h\k*:\)\@='
  elseif self.name() =~# '\.sql$'
    return s:sql_define
  endif
  let define = '^\s*def\s\+\(self\.\)\='
  if self.name() =~# '\.rake$'
    let define .= "\\\|^\\s*\\%(task\\\|file\\)\\s\\+[:'\"]"
  endif
  if self.name() =~# '/schema\.rb$'
    let define .= "\\\|^\\s*create_table\\s\\+[:'\"]"
  endif
  if self.name() =~# '\.erb$'
    let define .= '\|\<id=["'']\='
  endif
  if self.name() =~# '\.haml$'
    let define .= '\|^\s*\%(%\w*\)\=\%(\.[[:alnum:]_-]\+\)*#'
  endif
  if self.type_name('test')
    let define .= '\|^\s*test\s*[''"]'
  endif
  return define
endfunction

function! s:readable_last_method_line(start) dict abort
  return self.last_opening_line(a:start,self.define_pattern(),0)
endfunction

function! s:lastmethodline(start)
  return rails#buffer().last_method_line(a:start)
endfunction

function! s:readable_last_method(start) dict abort
  let lnum = self.last_method_line(a:start)
  let line = self.getline(lnum)
  if line =~# '^\s*test\s*\([''"]\).*\1'
    let string = matchstr(line,'^\s*\w\+\s*\([''"]\)\zs.*\ze\1')
    return 'test_'.s:gsub(string,' +','_')
  elseif lnum
    return s:sub(matchstr(line,'\%('.self.define_pattern().'\)\zs\h\%(\k\|[:.]\)*[?!=]\='),':$','')
  else
    return ""
  endif
endfunction

function! s:lastmethod(...)
  return rails#buffer().last_method(a:0 ? a:1 : line("."))
endfunction

function! s:readable_format(start) dict abort
  if a:start
    let format = matchstr(self.getline(a:start), '\%(:formats *=>\|\<formats:\) *\[\= *[:''"]\zs\w\+')
    if format !=# ''
      return format
    endif
  endif
  if self.type_name('view')
    let format = fnamemodify(self.path(),':r:e')
    if empty(format)
      return get({'rhtml': 'html', 'rxml': 'xml', 'rjs': 'js', 'haml': 'html'},
            \ matchstr(self.path(),'\.\zs\w\+$'), '')
    else
      return format
    endif
  endif
  if !a:start
    return ''
  endif
  let rline = self.last_opening_line(a:start,'\C^\s*\%(mail\>.*\|respond_to\)\s*\%(\<do\|{\)\s*|\zs\h\k*\ze|',self.last_method_line(a:start))
  if rline
    let variable = matchstr(self.getline(rline),'\C^\s*\%(mail\>.*\|respond_to\)\s*\%(\<do\|{\)\s*|\zs\h\k*\ze|')
    let line = a:start
    while line > rline
      let match = matchstr(self.getline(line),'\C^\s*'.variable.'\s*\.\s*\zs\h\k*')
      if match != ''
        return match
      endif
      let line -= 1
    endwhile
  endif
  return self.type_name('mailer') ? 'text' : 'html'
endfunction

function! s:format()
  return rails#buffer().format(line('.'))
endfunction

call s:add_methods('readable',['end_of','last_opening_line','last_method_line','last_method','format','define_pattern'])

function! s:readable_find_affinity() dict abort
  let f = self.name()
  let all = self.app().projections()
  for pattern in reverse(sort(filter(keys(all), 'v:val =~# "^[^*{}]*\\*[^*{}]*$"'), s:function('rails#lencmp')))
    if !has_key(all[pattern], 'affinity')
      continue
    endif
    let [prefix, suffix; _] = split(pattern, '\*', 1)
    if s:startswith(f, prefix) && s:endswith(f, suffix)
      let root = f[strlen(prefix) : -strlen(suffix)-1]
      return [all[pattern].affinity, root]
    endif
  endfor
  return ['', '']
endfunction

function! s:controller(...)
  return rails#buffer().controller_name(a:0 ? a:1 : 0)
endfunction

function! s:readable_controller_name(...) dict abort
  let f = self.name()
  if has_key(self,'getvar') && !empty(self.getvar('rails_controller'))
    return self.getvar('rails_controller')
  endif
  let [affinity, root] = self.find_affinity()
  if affinity ==# 'controller'
    return root
  elseif affinity ==# 'resource'
    return rails#pluralize(root)
  endif
  if f =~# '^app/views/layouts/'
    return s:sub(f,'^app/views/layouts/(.{-})\..*','\1')
  elseif f =~# '^app/views/'
    return s:sub(f,'^app/views/(.{-})/\w+%(\.[[:alnum:]_+]+)=\.\w+$','\1')
  elseif f =~# '^app/helpers/.*_helper\.rb$'
    return s:sub(f,'^app/helpers/(.{-})_helper\.rb$','\1')
  elseif f =~# '^app/controllers/.*\.rb$'
    return s:sub(f,'^app/controllers/(.{-})%(_controller)=\.rb$','\1')
  elseif f =~# '^app/mailers/.*\.rb$'
    return s:sub(f,'^app/mailers/(.{-})\.rb$','\1')
  elseif f =~# '^\%(test\|spec\)/mailers/previews/.*_preview\.rb$'
    return s:sub(f,'^%(test|spec)/mailers/previews/(.{-})_preview\.rb$','\1')
  elseif f =~# '^app/jobs/.*\.rb$'
    return s:sub(f,'^app/jobs/(.{-})%(_job)=\.rb$','\1')
  elseif f =~# '^test/\%(functional\|controllers\)/.*_test\.rb$'
    return s:sub(f,'^test/%(functional|controllers)/(.{-})%(_controller)=_test\.rb$','\1')
  elseif f =~# '^test/\%(unit/\)\?helpers/.*_helper_test\.rb$'
    return s:sub(f,'^test/%(unit/)?helpers/(.{-})_helper_test\.rb$','\1')
  elseif f =~# '^spec/controllers/.*_spec\.rb$'
    return s:sub(f,'^spec/controllers/(.{-})%(_controller)=_spec\.rb$','\1')
  elseif f =~# '^spec/jobs/.*_spec\.rb$'
    return s:sub(f,'^spec/jobs/(.{-})%(_job)=_spec\.rb$','\1')
  elseif f =~# '^spec/helpers/.*_helper_spec\.rb$'
    return s:sub(f,'^spec/helpers/(.{-})_helper_spec\.rb$','\1')
  elseif f =~# '^spec/views/.*/\w\+_view_spec\.rb$'
    return s:sub(f,'^spec/views/(.{-})/\w+_view_spec\.rb$','\1')
  elseif f =~# '^app/models/.*\.rb$' && self.type_name('mailer')
    return s:sub(f,'^app/models/(.{-})\.rb$','\1')
  elseif f =~# '^\%(public\|app/assets\)/stylesheets/[^.]\+\.'
    return s:sub(f,'^%(public|app/assets)/stylesheets/(.{-})\..*$','\1')
  elseif f =~# '^\%(public\|app/assets\)/javascripts/.[^.]\+\.'
    return s:sub(f,'^%(public|app/assets)/javascripts/(.{-})\..*$','\1')
  elseif a:0 && a:1
    return rails#pluralize(self.model_name())
  endif
  return ""
endfunction

function! s:model(...)
  return rails#buffer().model_name(a:0 ? a:1 : 0)
endfunction

function! s:readable_model_name(...) dict abort
  let f = self.name()
  if has_key(self,'getvar') && !empty(self.getvar('rails_model'))
    return self.getvar('rails_model')
  endif
  let [affinity, root] = self.find_affinity()
  if affinity ==# 'model'
    return root
  elseif affinity ==# 'collection'
    return rails#singularize(root)
  endif
  if f =~# '^app/models/.*_observer.rb$'
    return s:sub(f,'^app/models/(.*)_observer\.rb$','\1')
  elseif f =~# '^app/models/.*\.rb$'
    return s:sub(f,'^app/models/(.*)\.rb$','\1')
  elseif f =~# '^test/\%(unit\|models\)/.*_observer_test\.rb$'
    return s:sub(f,'^test/unit/(.*)_observer_test\.rb$','\1')
  elseif f =~# '^test/\%(unit\|models\)/.*_test\.rb$'
    return s:sub(f,'^test/%(unit|models)/(.*)_test\.rb$','\1')
  elseif f =~# '^spec/models/.*_spec\.rb$'
    return s:sub(f,'^spec/models/(.*)_spec\.rb$','\1')
  elseif f =~# '^\%(test\|spec\)/blueprints/.*\.rb$'
    return s:sub(f,'^%(test|spec)/blueprints/(.{-})%(_blueprint)=\.rb$','\1')
  elseif f =~# '^\%(test\|spec\)/exemplars/.*_exemplar\.rb$'
    return s:sub(f,'^%(test|spec)/exemplars/(.*)_exemplar\.rb$','\1')
  elseif f =~# '^\%(test/\|spec/\)\=factories/.*_factory\.rb$'
    return s:sub(f,'^%(test/|spec/)=factories/(.{-})_factory.rb$','\1')
  elseif f =~# '^\%(test/\|spec/\)\=fabricators/.*\.rb$'
    return s:sub(f,'^%(test/|spec/)=fabricators/(.{-})_fabricator.rb$','\1')
  elseif f =~# '^\%(test\|spec\)/\%(fixtures\|factories\|fabricators\)/.*\.\w\+$'
    return rails#singularize(s:sub(f,'^%(test|spec)/\w+/(.*)\.\w+$','\1'))
  elseif a:0 && a:1
    return rails#singularize(s:sub(self.controller_name(), '_mailer$', ''))
  endif
  return ""
endfunction

call s:add_methods('readable', ['find_affinity', 'controller_name', 'model_name'])

function! s:file_lines() dict abort
  let ftime = s:getftime(self.path())
  if ftime > get(self,'last_lines_ftime',0)
    let self.last_lines = s:readfile(self.path())
    let self.last_lines_ftime = ftime
  endif
  return get(self,'last_lines',[])
endfunction

function! s:file_getline(lnum,...) dict abort
  if a:0
    return self.lines()[a:lnum-1 : a:1-1]
  else
    return self.lines()[a:lnum-1]
  endif
endfunction

function! s:buffer_lines() dict abort
  return self.getline(1,'$')
endfunction

function! s:buffer_getline(...) dict abort
  if a:0 == 1
    return get(call('getbufline',[self.number()]+a:000),0,'')
  else
    return call('getbufline',[self.number()]+a:000)
  endif
endfunction

function! s:readable_line_count() dict abort
  return len(self.lines())
endfunction

function! s:environment()
  if exists('$RAILS_ENV')
    return $RAILS_ENV
  elseif exists('$RACK_ENV')
    return $RACK_ENV
  else
    return "development"
  endif
endfunction

function! s:Complete_environments(...) abort
  return s:completion_filter(rails#app().environments(),a:0 ? a:1 : "")
endfunction

function! s:warn(str) abort
  echohl WarningMsg
  echomsg a:str
  echohl None
  " Sometimes required to flush output
  echo ""
  let v:warningmsg = a:str
  return ''
endfunction

function! s:error(str) abort
  echohl ErrorMsg
  echomsg a:str
  echohl None
  let v:errmsg = a:str
  return ''
endfunction

function! s:debug(str)
  if exists("g:rails_debug") && g:rails_debug
    echohl Debug
    echomsg a:str
    echohl None
  endif
endfunction

function! s:buffer_getvar(varname) dict abort
  return getbufvar(self.number(),a:varname)
endfunction

function! s:buffer_setvar(varname, val) dict abort
  return setbufvar(self.number(),a:varname,a:val)
endfunction

call s:add_methods('buffer',['getvar','setvar'])

" }}}1
" Public Interface {{{1

function! rails#underscore(str, ...) abort
  let str = s:gsub(a:str,'::','/')
  let str = s:gsub(str,'(\u+)(\u\l)','\1_\2')
  let str = s:gsub(str,'(\l|\d)(\u)','\1_\2')
  let str = tolower(str)
  return a:0 && a:1 ? s:sub(str, '^/', '') : str
endfunction

function! rails#camelize(str) abort
  let str = s:gsub(a:str,'/(.=)','::\u\1')
  let str = s:gsub(str,'%([_-]|<)(.)','\u\1')
  return str
endfunction

function! rails#singularize(word) abort
  " Probably not worth it to be as comprehensive as Rails but we can
  " still hit the common cases.
  let word = a:word
  if word =~? '\.js$\|redis$' || empty(word)
    return word
  endif
  let word = s:sub(word,'eople$','ersons')
  let word = s:sub(word,'%([Mm]ov|[aeio])@<!ies$','ys')
  let word = s:sub(word,'xe[ns]$','xs')
  let word = s:sub(word,'ves$','fs')
  let word = s:sub(word,'ss%(es)=$','sss')
  let word = s:sub(word,'s$','')
  let word = s:sub(word,'%([nrt]ch|tatus|lias)\zse$','')
  let word = s:sub(word,'%(nd|rt)\zsice$','ex')
  return word
endfunction

function! rails#pluralize(word, ...) abort
  let word = a:word
  if empty(word)
    return word
  endif
  if a:0 && a:1 && word !=# rails#singularize(word)
    return word
  endif
  let word = s:sub(word,'[aeio]@<!y$','ie')
  let word = s:sub(word,'%(nd|rt)@<=ex$','ice')
  let word = s:sub(word,'%([sxz]|[cs]h)$','&e')
  let word = s:sub(word,'f@<!f$','ve')
  let word .= 's'
  let word = s:sub(word,'ersons$','eople')
  return word
endfunction

function! rails#app(...) abort
  let root = s:sub(a:0 && len(a:1) ? a:1 : get(b:, 'rails_root', ''), '[\/]$', '')
  if !empty(root)
    if !has_key(s:apps, root)
      let s:apps[root] = deepcopy(s:app_prototype)
      let s:apps[root]._root = root
    endif
    return get(s:apps, root, {})
  endif
  return {}
endfunction

function! rails#buffer(...)
  return extend(extend({'#': bufnr(a:0 ? a:1 : '%')},s:buffer_prototype,'keep'),s:readable_prototype,'keep')
endfunction

function! s:buffer_app() dict abort
  if len(self.getvar('rails_root'))
    return rails#app(self.getvar('rails_root'))
  else
    throw 'Not in a Rails app'
  endif
endfunction

function! s:readable_app() dict abort
  return self._app
endfunction

function! rails#revision() abort
  return 1000*matchstr(g:autoloaded_rails,'^\d\+')+matchstr(g:autoloaded_rails,'[1-9]\d*$')
endfunction

function! s:app_file(name) dict abort
  return extend(extend({'_app': self, '_name': a:name}, s:file_prototype,'keep'),s:readable_prototype,'keep')
endfunction

function! s:readable_relative() dict abort
  return self.name()
endfunction

function! s:readable_absolute() dict abort
  return self.path()
endfunction

function! s:readable_spec() dict abort
  return self.path()
endfunction

function! s:file_path() dict abort
  return self.app().path(self._name)
endfunction

function! s:file_name() dict abort
  return self._name
endfunction

function! s:buffer_number() dict abort
  return self['#']
endfunction

function! s:buffer_path() dict abort
  let bufname = bufname(self.number())
  return empty(bufname) ? '' : s:gsub(fnamemodify(bufname,':p'),'\\ @!','/')
endfunction

function! s:buffer_name() dict abort
  let app = self.app()
  let bufname = bufname(self.number())
  let f = len(bufname) ? fnamemodify(bufname, ':p') : ''
  if f !~# ':[\/][\/]'
    let f = resolve(f)
  endif
  let f = s:gsub(f, '\\ @!', '/')
  let f = s:sub(f,'/$','')
  let sep = matchstr(f,'^[^\\/:]\+\zs[\\/]')
  if len(sep)
    let f = getcwd().sep.f
  endif
  if s:startswith(tolower(f),s:gsub(tolower(app.path()),'\\ @!','/')) || f == ""
    return strpart(f,strlen(app.path())+1)
  else
    if !exists("s:path_warn") && &verbose
      let s:path_warn = 1
      call s:warn("File ".f." does not appear to be under the Rails root ".self.app().path().". Please report to the rails.vim author!")
    endif
    return f
  endif
endfunction

function! s:readable_calculate_file_type() dict abort
  let f = self.name()
  let e = matchstr(f, '\.\zs[^.\/]\+$')
  let ae = e
  if ae ==# 'erb'
    let ae = matchstr(f, '\.\zs[^.\/]\+\ze\.erb$')
  endif
  let r = "-"
  let full_path = self.path()
  if empty(f)
    let r = ""
  elseif f =~# '^app/controllers/concerns/.*\.rb$'
    let r = "controller-concern"
  elseif f =~# '_controller\.rb$' || f =~# '^app/controllers/.*\.rb$'
    let r = "controller"
  elseif f =~# '^test/test_helper\.rb$'
    let r = "test"
  elseif f =~# '^spec/\%(spec\|rails\)_helper\.rb$'
    let r = "spec"
  elseif f =~# '_helper\.rb$'
    let r = "helper"
  elseif f =~# '^app/mailers/.*\.rb'
    let r = "mailer"
  elseif f =~# '^\%(test\|spec\)/mailers/previews/.*_preview\.rb'
    let r = "mailerpreview"
  elseif f =~# '^app/jobs/.*\.rb'
    let r = "job"
  elseif f =~# '^app/models/concerns/.*\.rb$'
    let r = "model-concern"
  elseif f =~# '^app/models/'
    let top = "\n".join(s:readbuf(full_path,50),"\n")
    let class = matchstr(top,"\n".'class\s\+\S\+\s*<\s*\<\zs\S\+\>')
    let type = tolower(matchstr(class, '^Application\zs[A-Z]\w*$\|^Acti\w\w\zs[A-Z]\w*\ze::Base'))
    if type ==# 'mailer' || f =~# '_mailer\.rb$'
      let r = 'mailer'
    elseif class ==# 'ActiveRecord::Observer'
      let r = 'model-observer'
    elseif !empty(type)
      let r = 'model-'.type
    elseif top =~# '^\%(self\.\%(table_name\|primary_key\)\|has_one\|has_many\|belongs_to\)\>'
      let r = 'model-record'
    else
      let r = 'model'
    endif
  elseif f =~# '^app/views/.*/_\w\+\%(\.[[:alnum:]_+]\+\)\=\.\w\+$'
    let r = "view-partial-" . e
  elseif f =~# '^app/views/layouts\>.*\.'
    let r = "view-layout-" . e
  elseif f =~# '^app/views\>.*\.'
    let r = "view-" . e
  elseif f =~# '^test/unit/.*_helper\.rb$'
    let r = "test-helper"
  elseif f =~# '^test/unit/.*\.rb$'
    let r = "test-model"
  elseif f =~# '^test/functional/.*_controller_test\.rb$'
    let r = "test-controller"
  elseif f =~# '^test/integration/.*_test\.rb$'
    let r = "test-integration"
  elseif f =~# '^test/lib/.*_test\.rb$'
    let r = "test-lib"
  elseif f =~# '^test/\w*s/.*_test\.rb$'
    let r = s:sub(f,'.*<test/(\w*)s/.*','test-\1')
  elseif f =~# '^test/.*_test\.rb'
    let r = "test"
  elseif f =~# '^spec/lib/.*_spec\.rb$'
    let r = 'spec-lib'
  elseif f =~# '^lib/.*\.rb$'
    let r = 'lib'
  elseif f =~# '^spec/\w*s/.*_spec\.rb$'
    let r = s:sub(f,'.*<spec/(\w*)s/.*','spec-\1')
  elseif f =~# '^features/.*\.feature$'
    let r = 'cucumber-feature'
  elseif f =~# '^features/step_definitions/.*_steps\.rb$'
    let r = 'cucumber-steps'
  elseif f =~# '^features/.*\.rb$'
    let r = 'cucumber'
  elseif f =~# '^spec/.*\.feature$'
    let r = 'spec-feature'
  elseif f =~# '^\%(test\|spec\)/fixtures\>'
    if e ==# "yml"
      let r = "fixtures-yaml"
    else
      let r = "fixtures" . (empty(e) ? "" : "-" . e)
    endif
  elseif f =~# '^\%(test\|spec\)/\%(factories\|fabricators\)\>'
    let r = "fixtures-replacement"
  elseif f =~# '^spec/.*_spec\.rb'
    let r = "spec"
  elseif f =~# '^spec/support/.*\.rb'
    let r = "spec"
  elseif f =~# '^db/migrate\>'
    let r = "db-migration"
  elseif f=~# '^db/schema\.rb$'
    let r = "db-schema"
  elseif f =~# '\.rake$' || f =~# '^\%(Rake\|Cap\)file$' || f =~# '^config/deploy\.rb$' || f =~# '^config/deploy/.*\.rb$'
    let r = "task"
  elseif f =~# '^log/.*\.log$'
    let r = "log"
  elseif ae ==# "css" || ae =~# "^s[ac]ss$" || ae ==# "^less$"
    let r = "stylesheet-".ae
  elseif ae ==# "js" || ae ==# "es6"
    let r = "javascript"
  elseif ae ==# "coffee"
    let r = "javascript-coffee"
  elseif e ==# "html"
    let r = e
  elseif f =~# '^config/routes\>.*\.rb$'
    let r = "config-routes"
  elseif f =~# '^config/'
    let r = "config"
  endif
  return r
endfunction

function! s:buffer_type_name(...) dict abort
  let type = getbufvar(self.number(),'rails_cached_file_type')
  if empty(type)
    let type = self.calculate_file_type()
  endif
  return call('s:match_type',[type ==# '-' ? '' : type] + a:000)
endfunction

function! s:readable_type_name(...) dict abort
  let type = self.calculate_file_type()
  return call('s:match_type',[type ==# '-' ? '' : type] + a:000)
endfunction

function! s:match_type(type,...)
  if a:0
    return !empty(filter(copy(a:000),'a:type =~# "^".v:val."\\%(-\\|$\\)"'))
  else
    return a:type
  endif
endfunction

function! s:app_environments() dict
  if self.cache.needs('environments')
    call self.cache.set('environments',self.relglob('config/environments/','**/*','.rb'))
  endif
  return copy(self.cache.get('environments'))
endfunction

function! s:app_default_locale() dict abort
  if self.cache.needs('default_locale')
    let candidates = map(filter(
          \ s:readfile(self.path('config/application.rb')) + s:readfile(self.path('config/environment.rb')),
          \ 'v:val =~# "^ *config.i18n.default_locale = :[\"'']\\=[A-Za-z-]\\+[\"'']\\= *$"'
          \ ), 'matchstr(v:val,"[A-Za-z-]\\+\\ze[\"'']\\= *$")')
    call self.cache.set('default_locale', get(candidates, 0, 'en'))
  endif
  return self.cache.get('default_locale')
endfunction

function! s:app_stylesheet_suffix() dict abort
  if self.cache.needs('stylesheet_suffix')
    let default = self.has_gem('sass-rails') ? '.scss' : '.css'
    let candidates = map(filter(
          \ s:readfile(self.path('config/application.rb')),
          \ 'v:val =~# "^ *config.sass.preferred_syntax *= *:[A-Za-z-]\\+ *$"'
          \ ), '".".matchstr(v:val,"[A-Za-z-]\\+\\ze *$")')
    call self.cache.set('stylesheet_suffix', get(candidates, 0, default))
  endif
  return self.cache.get('stylesheet_suffix')
endfunction

function! s:app_has(feature) dict
  let map = {
        \'test': 'test/',
        \'spec': 'spec/',
        \'bundler': 'Gemfile|gems.locked',
        \'rails2': 'script/about',
        \'rails3': 'config/application.rb',
        \'rails5': 'app/assets/config/manifest.js|config/initializers/application_controller_renderer.rb',
        \'cucumber': 'features/',
        \'webpack': 'app/javascript/packs',
        \'turnip': 'spec/acceptance/',
        \'sass': 'public/stylesheets/sass/'}
  if self.cache.needs('features')
    call self.cache.set('features',{})
  endif
  let features = self.cache.get('features')
  if !has_key(features,a:feature)
    let path = get(map,a:feature,a:feature.'/')
    let features[a:feature] =
          \ !empty(filter(split(path, '|'), 'self.has_file(v:val)'))
  endif
  return features[a:feature]
endfunction

function! s:app_has_rails5() abort dict
  let gemdir = get(self.gems(), 'railties')
  return self.has('rails5') || gemdir =~# '-\%([5-9]\|\d\d\+\)\.[^\/]*$'
endfunction

call s:add_methods('app',['default_locale','environments','file','has','has_rails5','stylesheet_suffix'])
call s:add_methods('file',['path','name','lines','getline'])
call s:add_methods('buffer',['app','number','path','name','lines','getline','type_name'])
call s:add_methods('readable',['app','relative','absolute','spec','calculate_file_type','type_name','line_count'])

" }}}1
" Ruby Execution {{{1

function! s:app_has_zeus() dict abort
  return getftype(self.real('zeus.sock')) ==# 'socket' && executable('zeus')
endfunction

function! s:app_ruby_script_command(cmd) dict abort
  if has('win32')
    return 'ruby ' . a:cmd
  else
    return a:cmd
  endif
endfunction

function! s:app_static_rails_command(cmd) dict abort
  if filereadable(self.real('bin/rails'))
    let cmd = 'bin/rails '.a:cmd
  elseif filereadable(self.real('script/rails'))
    let cmd = 'script/rails '.a:cmd
  elseif !self.has('rails3')
    let cmd = 'script/'.a:cmd
  elseif self.has('bundler')
    return 'bundle exec rails ' . a:cmd
  else
    return 'rails '.a:cmd
  endif
  return self.ruby_script_command(cmd)
endfunction

function! s:app_prepare_rails_command(cmd) dict abort
  if self.has_zeus() && a:cmd =~# '^\%(console\|dbconsole\|destroy\|generate\|server\|runner\)\>'
    return 'zeus '.a:cmd
  endif
  return self.static_rails_command(a:cmd)
endfunction

function! s:app_start_rails_command(cmd, ...) dict abort
  let cmd = s:esccmd(self.prepare_rails_command(a:cmd))
  let title = s:sub(a:cmd, '\s.*', '')
  let title = get({
        \ 'g': 'generate',
        \ 'd': 'destroy',
        \ 'c': 'console',
        \ 'db': 'dbconsole',
        \ 's': 'server',
        \ 'r': 'runner',
        \ }, title, title)
  call s:push_chdir(1)
  try
    if exists(':Start') == 2
      let title = escape(fnamemodify(self.path(), ':t').' '.title, ' ')
      exe 'Start'.(a:0 && a:1 ? '!' : '').' -title='.title.' '.cmd
    elseif has("win32")
      exe "!start ".cmd
    else
      exe "!".cmd
    endif
  finally
    call s:pop_command()
  endtry
  return ''
endfunction

function! s:app_execute_rails_command(cmd) dict abort
  call s:push_chdir(1)
  try
    exe '!'.s:esccmd(self.prepare_rails_command(a:cmd))
  finally
    call s:pop_command()
  endtry
  return ''
endfunction

call s:add_methods('app', ['has_zeus', 'ruby_script_command','static_rails_command','prepare_rails_command','execute_rails_command','start_rails_command'])

" }}}1
" Commands {{{1

function! s:BufCommands()
  call s:BufNavCommands()
  call s:BufScriptWrappers()
  command! -buffer -bar -nargs=* -bang Rabbrev :echoerr "Rabbrev has been removed."
  command! -buffer -bar -nargs=? -bang -count -complete=customlist,rails#complete_rake Rake    :call s:Rake(<bang>0,!<count> && <line1> ? -1 : <count>,<q-args>)
  command! -buffer -bar -nargs=? -bang -range -complete=customlist,s:Complete_preview Rbrowse :call s:Preview(<bang>0,<line1>,<q-args>)
  command! -buffer -bar -nargs=? -bang -range -complete=customlist,s:Complete_preview Preview :call s:Preview(<bang>0,<line1>,<q-args>)
  command! -buffer -bar -nargs=? -bang -complete=customlist,s:Complete_log            Clog     exe s:Clog(1<bang>, '<mods>', <q-args>)
  command! -buffer -bar -nargs=0 Rtags       :echoerr "Use :Ctags"
  command! -buffer -bar -nargs=0 Ctags       :execute rails#app().tags_command()
  command! -buffer -bar -nargs=0 -bang Rrefresh :if <bang>0|unlet! g:autoloaded_rails|source `=s:file`|endif|call s:Refresh(<bang>0)
  if exists("g:loaded_dbext")
    command! -buffer -bar -nargs=? -complete=customlist,s:Complete_environments Rdbext  :echoerr 'Install dadbod.vim and let g:dadbod_manage_dbext = 1'
  endif
  let ext = expand("%:e")
  if rails#buffer().name() =~# '^app/views/'
    " TODO: complete controller names with trailing slashes here
    command! -buffer -bar -bang -nargs=1 -range -complete=customlist,s:controllerList Extract  :exe s:ViewExtract(<bang>0,'<mods>',<line1>,<line2>,<f-args>)
  elseif rails#buffer().name() =~# '^app/helpers/.*\.rb$'
    command! -buffer -bar -bang -nargs=1 -range Extract  :<line1>,<line2>call s:RubyExtract(<bang>0, '<mods>', 'app/helpers', [], s:sub(<f-args>, '_helper$|Helper$|$', '_helper'))
  elseif rails#buffer().name() =~# '^app/\w\+/.*\.rb$'
    command! -buffer -bar -bang -nargs=1 -range Extract  :<line1>,<line2>call s:RubyExtract(<bang>0, '<mods>', matchstr(rails#buffer().name(), '^app/\w\+/').'concerns', ['  extend ActiveSupport::Concern', ''], <f-args>)
  endif
  if rails#buffer().name() =~# '^db/migrate/.*\.rb$'
    command! -buffer -bar                 Rinvert  :call s:Invert(<bang>0)
  endif
endfunction

function! s:Complete_log(A, L, P) abort
  return s:completion_filter(rails#app().relglob('log/','**/*', '.log'), a:A)
endfunction

function! s:Clog(bang, mods, arg) abort
  let lf = rails#app().real('log/' . (empty(a:arg) ? s:environment() : a:arg) . '.log')
  if !filereadable(lf)
    return 'cgetfile ' . s:fnameescape(lf)
  endif
  let [mp, efm, cc] = [&l:mp, &l:efm, get(b:, 'current_compiler', '')]
  let chdir = exists("*haslocaldir") && haslocaldir() ? 'lchdir' : 'chdir'
  let cwd = getcwd()
  try
    compiler rails
    exe chdir s:fnameescape(rails#app().real())
    exe 'cgetfile' s:fnameescape(lf)
  finally
    let [&l:mp, &l:efm, b:current_compiler] = [mp, efm, cc]
    if empty(cc) | unlet! b:current_compiler | endif
    exe chdir s:fnameescape(cwd)
  endtry
  return s:mods(a:mods) . ' copen|$'
endfunction

function! s:Plog(bang, arg) abort
  let lf = rails#app().path('log/' . (empty(a:arg) ? s:environment() : a:arg) . '.log')
  return 'pedit' . (a:bang ? '!' : '') . ' +$ ' . s:fnameescape(lf)
endfunction

function! rails#command(bang, mods, count, arg) abort
  if s:active()
    return s:Rails(a:bang, a:count, a:arg)
  elseif a:arg !~# '^new\>'
    return 'echoerr '.string('Usage: rails new <path>')
  endif

  let arg = a:arg

  if &shellpipe !~# 'tee' && arg !~# ' --\%(skip\|force\)\>'
    let arg .= ' --skip'
  endif

  let temp = tempname()
  try
    if &shellpipe =~# '%s'
      let pipe = s:sub(&shellpipe, '\%s', temp)
    else
      let pipe = &shellpipe . ' ' . temp
    endif
    exe '!rails' arg pipe
    let error = v:shell_error
  catch /^Vim:Interrupt/
  endtry

  let dir = matchstr(arg, ' ["'']\=\zs[^- "''][^ "'']\+')
  if isdirectory(dir)
    let old_errorformat = &l:errorformat
    let chdir = exists("*haslocaldir") && haslocaldir() ? 'lchdir' : 'chdir'
    let cwd = getcwd()
    try
      exe chdir s:fnameescape(dir)
      let &l:errorformat = s:efm_generate
      exe 'cgetfile' temp
      return 'copen|cfirst'
    finally
      let &l:errorformat = old_errorformat
      exe chdir s:fnameescape(cwd)
    endtry
  elseif exists('error') && !error && !empty(dir)
    call s:warn("Couldn't find app directory")
  endif
  return ''
endfunction

function! s:app_tags_command() dict abort
  if exists("g:Tlist_Ctags_Cmd")
    let cmd = g:Tlist_Ctags_Cmd
  elseif executable("exuberant-ctags")
    let cmd = "exuberant-ctags"
  elseif executable("ctags-exuberant")
    let cmd = "ctags-exuberant"
  elseif executable("exctags")
    let cmd = "exctags"
  elseif executable("ctags")
    let cmd = "ctags"
  elseif executable("ctags.exe")
    let cmd = "ctags.exe"
  else
    call s:error("ctags not found")
    return ''
  endif
  let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : 'cd'
  let cwd = getcwd()
  try
    execute cd fnameescape(self.real())
    if filereadable('.ctags')
      let args = []
    else
      let args = s:split(get(g:, 'rails_ctags_arguments', '--languages=Ruby'))
    endif
    exe '!'.cmd.' -R '.join(args,' ')
  finally
    execute cd fnameescape(cwd)
  endtry
  return ''
endfunction

call s:add_methods('app',['tags_command'])

function! s:Refresh(bang)
  if exists("g:rubycomplete_rails") && g:rubycomplete_rails && has("ruby") && exists('g:rubycomplete_completions')
    silent! ruby ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
    silent! ruby if defined?(ActiveSupport::Dependencies); ActiveSupport::Dependencies.clear; elsif defined?(Dependencies); Dependencies.clear; end
    if a:bang
      silent! ruby ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
    endif
  endif
  let _ = rails#app().cache.clear()
  if exists('#User#BufLeaveRails')
    try
      let [modelines, &modelines] = [&modelines, 0]
      doautocmd User BufLeaveRails
    finally
      let &modelines = modelines
    endtry
  endif
  if a:bang
    for key in keys(s:apps)
      if type(s:apps[key]) == type({})
        call s:apps[key].cache.clear()
      endif
      call extend(s:apps[key],filter(copy(s:app_prototype),'type(v:val) == type(function("tr"))'),'force')
    endfor
  endif
  let i = 1
  let max = bufnr('$')
  while i <= max
    let rr = getbufvar(i,"rails_root")
    if !empty(rr)
      call setbufvar(i,"rails_refresh",1)
    endif
    let i += 1
  endwhile
  if exists('#User#BufEnterRails')
    try
      let [modelines, &modelines] = [&modelines, 0]
      doautocmd User BufEnterRails
    finally
      let &modelines = modelines
    endtry
  endif
endfunction

" }}}1
" Rake {{{1

function! s:efm_dir() abort
  return substitute(matchstr(','.&l:errorformat, ',%\\&chdir \zs\%(\\.\|[^,]\)*'), '\\,' ,',', 'g')
endfunction

function! s:qf_pre() abort
  let dir = s:efm_dir()
  let cwd = getcwd()
  if !empty(dir) && dir !=# cwd
    let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : 'cd'
    execute 'lcd' fnameescape(dir)
    let s:qf_post = cd . ' ' . fnameescape(cwd)
  endif
endfunction

augroup railsPluginMake
  autocmd!
  autocmd QuickFixCmdPre  *make* call s:qf_pre()
  autocmd QuickFixCmdPost *make*
        \ if exists('s:qf_post') | execute remove(s:, 'qf_post') | endif
augroup END

function! s:app_rake_tasks() dict abort
  if self.cache.needs('rake_tasks')
    call s:push_chdir()
    try
      let output = system(self.rake_command('norails').' -T')
      let lines = split(output, "\n")
    finally
      call s:pop_command()
    endtry
    if v:shell_error != 0
      return []
    endif
    call map(lines,'matchstr(v:val,"^\\S\\+\\s\\+\\zs[^][ ]\\+")')
    call filter(lines,'v:val != ""')
    call self.cache.set('rake_tasks',s:uniq(['default'] + lines))
  endif
  return self.cache.get('rake_tasks')
endfunction

call s:add_methods('app', ['rake_tasks'])

function! s:make(bang, args, ...)
  if exists(':Make') == 2
    exe 'Make'.(a:bang ? '! ' : ' ').a:args
  else
    exe 'make! '.a:args
    let qf = &l:buftype ==# 'quickfix'
    if !a:bang
      exe (a:0 ? a:1 : 'cwindow')
      if !qf && &l:buftype ==# 'quickfix'
        wincmd p
      endif
    endif
  endif
endfunction

function! s:Rake(bang, lnum, arg) abort
  let self = rails#app()
  let lnum = a:lnum < 0 ? 0 : a:lnum
  let old_makeprg = &l:makeprg
  let old_errorformat = &l:errorformat
  let old_compiler = get(b:, 'current_compiler', '')
  try
    compiler rails
    let b:current_compiler = 'rake'
    let &l:makeprg = rails#app().rake_command('norails')
    let &l:errorformat .= ',chdir '.escape(self.path(), ',')
    let arg = a:arg
    if arg == ''
      let arg = rails#buffer().default_rake_task(lnum)
    endif
    if !has_key(self,'options') | let self.options = {} | endif
    if arg == '-'
      let arg = get(self.options,'last_rake_task','')
    endif
    let self.options['last_rake_task'] = arg
    if arg =~# '^notes\>'
      let &l:errorformat = '%-P%f:,\ \ *\ [%\ %#%l]\ [%t%*[^]]] %m,\ \ *\ [%[\ ]%#%l] %m,%-Q'
      call s:make(a:bang, arg)
    elseif arg =~# '^\%(stats\|routes\|secret\|middleware\|time:zones\|db:\%(charset\|collation\|fixtures:identify\>.*\|migrate:status\|version\)\)\%([: ]\|$\)'
      let &l:errorformat = '%D(in\ %f),%+G%.%#'
      call s:make(a:bang, arg, 'copen')
    else
      call s:make(a:bang, arg)
    endif
  finally
    let &l:errorformat = old_errorformat
    let &l:makeprg = old_makeprg
    let b:current_compiler = old_compiler
    if empty(b:current_compiler)
      unlet b:current_compiler
    endif
  endtry
endfunction

function! s:readable_test_file_candidates() dict abort
  let f = self.name()
  let projected = self.projected('railsTest') + self.projected('test')
  if self.type_name('view')
    let tests = [
          \ fnamemodify(f,':s?\<app/?spec/?')."_spec.rb",
          \ fnamemodify(f,':r:s?\<app/?spec/?')."_spec.rb",
          \ fnamemodify(f,':r:r:s?\<app/?spec/?')."_spec.rb",
          \ s:sub(s:sub(f,'<app/views/','test/controllers/'),'/[^/]*$','_controller_test.rb'),
          \ s:sub(s:sub(f,'<app/views/','test/functional/'),'/[^/]*$','_controller_test.rb')]
  elseif self.type_name('lib')
    let tests = [
          \ s:sub(f,'<lib/(.*)\.rb$','test/lib/\1_test.rb'),
          \ s:sub(f,'<lib/(.*)\.rb$','test/unit/\1_test.rb'),
          \ s:sub(f,'<lib/(.*)\.rb$','spec/lib/\1_spec.rb')]
  elseif self.type_name('fixtures') && f =~# '\<spec/'
    let tests = [
          \ 'spec/models/' . self.model_name() . '_spec.rb']
  elseif self.type_name('fixtures')
    let tests = [
          \ 'test/models/' . self.model_name() . '_test.rb',
          \ 'test/unit/' . self.model_name() . '_test.rb']
  elseif f =~# '\<app/.*/.*\.rb'
    let file = fnamemodify(f,":r")
    let test_file = s:sub(file,'<app/','test/') . '_test.rb'
    let spec_file = s:sub(file,'<app/','spec/') . '_spec.rb'
    let old_test_file = s:sub(s:sub(s:sub(s:sub(test_file,
          \ '<test/helpers/', 'test/unit/helpers/'),
          \ '<test/models/', 'test/unit/'),
          \ '<test/mailers/', 'test/functional/'),
          \ '<test/controllers/', 'test/functional/')
    let tests = s:uniq([test_file, old_test_file, spec_file])
  elseif f =~# '\<\(test\|spec\)/\%(\1_helper\.rb$\|support\>\)' || f =~# '\%(\<spec/\|\<test/\)\@<!\<features/.*\.rb$'
    let tests = [matchstr(f, '.*\<\%(test\|spec\|features\)\>')]
  elseif self.type_name('test', 'spec', 'cucumber')
    let tests = [f]
  else
    let tests = []
  endif
  if !self.app().has('test')
    call filter(tests, 'v:val !~# "^test/"')
  endif
  if !self.app().has('spec')
    call filter(tests, 'v:val !~# "^spec/"')
  endif
  if !self.app().has('cucumber')
    call filter(tests, 'v:val !~# "^cucumber/"')
  endif
  return projected + tests
endfunction

function! s:readable_test_file() dict abort
  let candidates = self.test_file_candidates()
  for file in candidates
    if self.app().has_path(file)
      return file
    endif
  endfor
  return get(candidates, 0, '')
endfunction

function! s:readable_placeholders(lnum) dict abort
  let placeholders = {}
  if a:lnum
    let placeholders.lnum = a:lnum
    let placeholders.line = a:lnum
    let last = self.last_method(a:lnum)
    if !empty(last)
      let placeholders.define = last
    endif
  endif
  return placeholders
endfunction

function! s:readable_default_rake_task(...) dict abort
  let app = self.app()
  let lnum = a:0 ? (a:1 < 0 ? 0 : a:1) : 0

  let taskpat = '\C# ra\%(ils\|ke\)\s\+\zs.\{-\}\ze\%(\s\s\|#\|$\)'
  if self.getvar('&buftype') == 'quickfix'
    return '-'
  elseif self.getline(lnum) =~# '# ra\%(ils\|ke\) \S'
    return matchstr(self.getline(lnum),'\C# ra\%(ils\|ke\) \zs.*')
  elseif self.getline(self.last_method_line(lnum)-1) =~# taskpat
    return matchstr(self.getline(self.last_method_line(lnum)-1), taskpat)
  elseif self.getline(self.last_method_line(lnum)) =~# taskpat
    return matchstr(self.getline(self.last_method_line(lnum)), taskpat)
  elseif self.getline(1) =~# taskpat && !lnum
    return matchstr(self.getline(1), taskpat)
  endif

  let placeholders = self.placeholders(lnum)
  let tasks = self.projected('rakeTask', placeholders) + self.projected('task', placeholders)
  if len(tasks)
    return tasks[0]
  endif
  let tasks = self.projected('railsTask', placeholders)
  if len(tasks)
    let task = substitute(tasks[0], '^$', '--tasks', '')
    if task =~# '^test\>'
      let task = substitute(substitute(task, ' \zs[^-[:upper:][:space:]]', 'TEST=', ''), ' -n', ' TESTOPTS=-n', '')
    endif
    return task
  endif

  if self.type_name('config-routes')
    return 'routes'
  elseif self.type_name('fixtures-yaml') && lnum
    return "db:fixtures:identify LABEL=".self.last_method(lnum)
  elseif self.type_name('fixtures') && lnum == 0
    return "db:fixtures:load FIXTURES=".s:sub(fnamemodify(self.name(),':r'),'^.{-}/fixtures/','')
  elseif self.type_name('task')
    let mnum = self.last_method_line(lnum)
    let line = getline(mnum)
    " We can't grab the namespace so only run tasks at the start of the line
    if line =~# '^\%(task\|file\)\>'
      let task = self.last_method(lnum)
    else
      let task = matchstr(self.getline(1),'\C# rake \zs.*')
    endif
    return s:sub(task, '^$', '--tasks')
  elseif self.type_name('db-migration')
    let ver = matchstr(self.name(),'\<db/migrate/0*\zs\d*\ze_')
    if !empty(ver)
      if lnum
        return "db:migrate:down VERSION=".ver
      else
        return "db:migrate:redo VERSION=".ver
      endif
    else
      return 'db:migrate'
    endif
  elseif self.name() =~# '\<db/seeds\.rb$'
    return 'db:seed'
  elseif self.name() =~# '\<db/\|\<config/database\.'
    return 'db:migrate:status'
  elseif self.name() =~# '\<config\.ru$'
    return 'middleware'
  elseif self.name() =~# '\<README'
    return 'about'
  else
    let test = self.test_file()
    let with_line = test
    if test ==# self.name()
      let with_line .= (lnum > 0 ? ':'.lnum : '')
    endif
    if empty(test)
      return '--tasks'
    elseif test =~# '^test\>'
      let opts = ''
      if test ==# self.name()
        let method = self.app().file(test).last_method(lnum)
        if method =~ '^test_'
          let opts = ' TESTOPTS=-n'.method
        endif
      endif
      if self.app().has_rails5()
        return 'test TEST='.s:rquote(test).opts
      elseif test =~# '^test/\%(unit\|models\|jobs\)\>'
        return 'test:units TEST='.s:rquote(test).opts
      elseif test =~# '^test/\%(functional\|controllers\)\>'
        return 'test:functionals TEST='.s:rquote(test).opts
      elseif test =~# '^test/integration\>'
        return 'test:integration TEST='.s:rquote(test).opts
      elseif test ==# 'test'
        return 'test'
      else
        return 'test:units TEST='.s:rquote(test).opts
      endif
    elseif test =~# '^spec\>'
      return 'spec SPEC='.s:rquote(with_line)
    elseif test =~# '^features\>'
      return 'cucumber FEATURE='.s:rquote(with_line)
    else
      let task = matchstr(test, '^\w*')
      return task . ' ' . toupper(task) . '=' . s:rquote(with_line)
    endif
  endif
endfunction

function! s:rake2rails(task) abort
  let task = s:gsub(a:task, '^--tasks$', '--help')
  let task = s:gsub(task, '<TEST\w*\=', '')
  return task
endfunction

function! s:readable_default_task(...) dict abort
  let tasks = self.projected('railsTask', self.placeholders(a:0 ? a:1 : 0))
  if len(tasks)
    return tasks[0]
  endif
  return s:rake2rails(call(self.default_rake_task, a:000, self))
endfunction

function! s:app_rake_command(...) dict abort
  let cmd = 'rake'
  if self.has_rails5() && get(a:, 1, '') !=# 'norails' && get(g:, 'rails_make', '') !=# 'rake'
    let cmd = 'rails'
  endif
  if get(a:, 1, '') !=# 'static' && self.has_zeus()
    return 'zeus ' . cmd
  elseif filereadable(self.real('bin/' . cmd))
    return self.ruby_script_command('bin/' . cmd)
  elseif self.has('bundler')
    return 'bundle exec ' . cmd
  else
    return cmd
  endif
endfunction

function! rails#complete_rake(A,L,P) abort
  return s:completion_filter(rails#app().rake_tasks(), a:A, ':')
endfunction

call s:add_methods('readable', ['test_file_candidates', 'test_file', 'placeholders', 'default_rake_task', 'default_task'])
call s:add_methods('app', ['rake_command'])

" }}}1
" Preview {{{1

function! s:initOpenURL() abort
  if exists(":OpenURL") != 2
    if exists(":Browse") == 2
      command -bar -nargs=1 OpenURL Browse <args>
    elseif has("gui_mac") || has("gui_macvim") || exists("$SECURITYSESSIONID")
      command -bar -nargs=1 OpenURL exe '!open' shellescape(<q-args>, 1)
    elseif has("gui_win32")
      command -bar -nargs=1 OpenURL exe '!start cmd /cstart /b' shellescape(<q-args>, 1)
    elseif executable("xdg-open")
      command -bar -nargs=1 OpenURL exe '!xdg-open' shellescape(<q-args>, 1) '&'
    elseif executable("sensible-browser")
      command -bar -nargs=1 OpenURL exe '!sensible-browser' shellescape(<q-args>, 1)
    elseif executable('launchy')
      command -bar -nargs=1 OpenURL exe '!launchy' shellescape(<q-args>, 1)
    elseif executable('git')
      command -bar -nargs=1 OpenURL exe '!git web--browse' shellescape(<q-args>, 1)
    endif
  endif
endfunction

function! s:scanlineforuris(line) abort
  let url = matchstr(a:line,"\\v\\C%(%(GET|PUT|POST|DELETE)\\s+|\\w+://[^/]*)/[^ \n\r\t<>\"]*[^] .,;\n\r\t<>\":]")
  if url =~# '^\u\+\s\+'
    let method = matchstr(url,'^\u\+')
    let url = matchstr(url,'\s\+\zs.*')
    if method !=? "GET"
      let url .= (url =~# '?' ? '&' : '?') . '_method='.tolower(method)
    endif
  endif
  if len(url)
    return [url]
  else
    return []
  endif
endfunction

function! s:readable_params(...) dict abort
  let lnum = a:0 ? a:1 : 0
  let params = {}
  let controller = self.controller_name(1)
  if len(controller)
    let params.controller = controller
  endif
  if self.type_name('controller') && len(self.last_method(lnum))
    let params.action = self.last_method(lnum)
  elseif self.type_name('controller','view-layout','view-partial')
    let params.action = 'index'
  elseif self.type_name('view')
    let params.action = fnamemodify(self.name(),':t:r:r:r')
    let format = fnamemodify(self.name(), ':r:e')
    if len(format) && format !=# 'html'
      let params.format = format
    endif
  endif
  for item in reverse(self.projected('railsParams') + self.projected('params'))
    if type(item) == type({})
      call extend(params, item)
    endif
  endfor
  return params
endfunction

function! s:expand_url(url, params) abort
  let params = extend({'controller': "\030", 'action': "\030", 'format': "\030"}, a:params, 'keep')
  let url = substitute(a:url, '\%(/\(\w\+\)/\)\=\zs[:*]\(\h\w*\)',
        \ '\=strftime(get(s:split(get(params,rails#singularize(submatch(1))."_".submatch(2),get(params,submatch(2),1))), 0, "\030"))', 'g')
  let url = s:gsub(url, '\([^()]*'."\030".'[^()]*\)', '')
  let url = s:gsub(url, '[()]', '')
  if url !~# "\030"
    return url
  else
    return ''
  endif
endfunction

function! s:readable_preview_urls(lnum) dict abort
  let urls = []
  let start = self.last_method_line(a:lnum) - 1
  while start > 0 && self.getline(start) =~# '^\s*\%(\%(-\=\|<%\)#.*\)\=$'
    let urls = s:scanlineforuris(self.getline(start)) + urls
    let start -= 1
  endwhile
  let start = 1
  while start < self.line_count() && self.getline(start) =~# '^\s*\%(\%(-\=\|<%\)#.*\)\=$'
    let urls += s:scanlineforuris(self.getline(start))
    let start += 1
  endwhile
  if has_key(self,'getvar') && len(self.getvar('rails_preview'))
    let urls += [self.getvar('rails_preview')]
  endif
  if self.name() =~# '^public/stylesheets/sass/'
    let urls = urls + [s:sub(s:sub(self.name(),'^public/stylesheets/sass/','/stylesheets/'),'\.s[ac]ss$','.css')]
  elseif self.name() =~# '^public/'
    let urls = urls + [s:sub(self.name(),'^public','')]
  elseif self.name() =~# '^\%(app\|lib\|vendor\)/assets/stylesheets/'
    call add(urls, '/assets/' . matchstr(self.name(), 'stylesheets/\zs[^.]*') . '.css')
  elseif self.name() =~# '^\%(app\|lib\|vendor\)/assets/javascripts/'
    call add(urls, '/assets/' . matchstr(self.name(), 'javascripts/\zs[^.]*') . '.js')
  elseif self.name() =~# '^app/javascript/packs/'
    let file = matchstr(self.name(), 'packs/\zs.\{-\}\%(\.erb\)\=$')
    if file =~# escape(join(rails#pack_suffixes('css'), '\|'), '.') . '$'
      let file = fnamemodify(file, ':r') . '.css'
    elseif file =~# escape(join(rails#pack_suffixes('js'), '\|'), '.') . '$'
      let file = fnamemodify(file, ':r') . '.js'
    endif
    if filereadable(self.app().real('public/packs/manifest.json'))
      let manifest = rails#json_parse(readfile(self.app().real('public/packs/manifest.json')))
    else
      let manifest = {}
    endif
    if has_key(manifest, file)
      call add(urls, manifest[file])
    else
      call add(urls, '/packs/' . file)
    endif
  elseif self.app().has_file('app/mailers/' . self.controller_name() . '.rb')
    if self.type_name('mailer', 'mailerpreview') && len(self.last_method(a:lnum))
      call add(urls, '/rails/mailers/' . self.controller_name() . '/' . self.last_method(a:lnum))
    elseif self.type_name('view')
      call add(urls, '/rails/mailers/' . self.controller_name() . '/' . fnamemodify(self.name(),':t:r:r:r'))
    endif
  else
    let params = self.params()
    let handler = get(params, 'controller', '') . '#' . get(params, 'action', '')
    for route in self.app().routes()
      if get(route, 'method') =~# 'GET' && get(route, 'handler') =~# '^:\=[[:alnum:]_/]*#:\=\w*$' && handler =~# '^'.s:gsub(route.handler, ':\w+', '\\w\\+').'$'
        call add(urls, s:expand_url(route.path, params))
      endif
    endfor
  endif
  return urls
endfunction

call s:add_methods('readable', ['params', 'preview_urls'])

function! s:app_server_pid() dict abort
  for type in ['server', 'unicorn']
    let pidfile = self.real('tmp/pids/'.type.'.pid')
    if filereadable(pidfile)
      let pid = get(readfile(pidfile, 'b', 1), 0, 0)
      if pid
        return pid
      endif
    endif
  endfor
endfunction

function! s:app_server_binding() dict abort
  let pid = self.server_pid()
  if pid
    if self.cache.needs('server')
      let old = {'pid': 0, 'binding': ''}
    else
      let old = self.cache.get('server')
    endif
    if !empty(old.binding) && pid == old.pid
      return old.binding
    endif
    let binding = rails#get_binding_for(pid)
    call self.cache.set('server', {'pid': pid, 'binding': binding})
    if !empty(binding)
      return binding
    endif
  endif
  for app in s:split(glob("~/.pow/*"))
    if resolve(app) ==# resolve(self.path())
      return fnamemodify(app, ':t').'.dev'
    endif
  endfor
  return ''
endfunction

call s:add_methods('app', ['server_pid', 'server_binding'])

function! s:Preview(bang, lnum, uri) abort
  let binding = rails#app().server_binding()
  if empty(binding)
    let binding = '0.0.0.0:3000'
  endif
  let binding = s:sub(binding, '^0\.0\.0\.0>|^127\.0\.0\.1>', 'localhost')
  let binding = s:sub(binding, '^\[::\]', '[::1]')
  let uri = empty(a:uri) ? get(rails#buffer().preview_urls(a:lnum),0,'') : a:uri
  if uri =~ '://'
    "
  elseif uri =~# '^[[:alnum:]-]\+\.'
    let uri = 'http://'.s:sub(uri, '^[^/]*\zs', matchstr(root, ':\d\+$'))
  elseif uri =~# '^[[:alnum:]-]\+\%(/\|$\)'
    let domain = s:sub(binding, '^localhost>', 'lvh.me')
    let uri = 'http://'.s:sub(uri, '^[^/]*\zs', '.'.domain)
  else
    let uri = 'http://'.binding.'/'.s:sub(uri,'^/','')
  endif
  call s:initOpenURL()
  if (exists(':OpenURL') == 2) && !a:bang
    exe 'OpenURL '.uri
  else
    " Work around bug where URLs ending in / get handled as FTP
    let url = uri.(uri =~ '/$' ? '?' : '')
    silent exe 'pedit '.url
    let root = rails#app().path()
    wincmd w
    let b:rails_root = root
    if &filetype ==# ''
      if uri =~ '\.css$'
        setlocal filetype=css
      elseif uri =~ '\.js$'
        setlocal filetype=javascript
      elseif getline(1) =~ '^\s*<'
        setlocal filetype=xhtml
      endif
    endif
    call rails#buffer_setup()
    map <buffer> <silent> q :bwipe<CR>
    wincmd p
    if !a:bang
      call s:warn("Define a :OpenURL command to use a browser")
    endif
  endif
endfunction

function! s:Complete_preview(A,L,P) abort
  return rails#buffer().preview_urls(a:L =~ '^\d' ? matchstr(a:L,'^\d\+') : line('.'))
endfunction

" }}}1
" Script Wrappers {{{1

function! s:BufScriptWrappers()
  command! -buffer -bang -bar -nargs=* -complete=customlist,s:Complete_environments Console   :Rails<bang> console <args>
  command! -buffer -bang -bar -nargs=* -complete=customlist,s:Complete_generate Generate      :execute rails#app().generator_command(<bang>0,'<mods>','generate',<f-args>)
  command! -buffer -bar -nargs=*       -complete=customlist,s:Complete_destroy  Destroy       :execute rails#app().generator_command(1,'<mods>','destroy',<f-args>)
  command! -buffer -bar -nargs=? -bang -complete=customlist,s:Complete_server   Server        :execute rails#app().server_command(0, <bang>0, <q-args>)
  command! -buffer -bang -nargs=? -range=0 -complete=customlist,s:Complete_edit Runner        :execute rails#buffer().runner_command(<bang>0, <count>?<line1>:0, <q-args>)
  command! -buffer       -nargs=1 -range=0 -complete=customlist,s:Complete_ruby Rp            :execute rails#app().output_command(<count>==<line2>?<count>:-1, 'p begin '.<q-args>.' end')
  command! -buffer       -nargs=1 -range=0 -complete=customlist,s:Complete_ruby Rpp           :execute rails#app().output_command(<count>==<line2>?<count>:-1, 'require %{pp}; pp begin '.<q-args>.' end')
endfunction

function! s:app_generators() dict abort
  if self.cache.needs('generators')
    let paths = [self.path('vendor/plugins/*'), self.path('lib'), expand("~/.rails")]
    if !empty(self.gems())
      let gems = values(self.gems())
      let paths += map(copy(gems), 'v:val . "/lib/rails"')
      let paths += map(gems, 'v:val . "/lib"')
      let builtin = []
    else
      let builtin = ['assets', 'controller', 'generator', 'helper', 'integration_test', 'jbuilder', 'jbuilder_scaffold_controller', 'mailer', 'migration', 'model', 'resource', 'scaffold', 'scaffold_controller', 'task', 'job']
    endif
    let generators = s:split(globpath(s:pathjoin(paths), 'generators/**/*_generator.rb'))
    call map(generators, 's:sub(v:val,"^.*[\\\\/]generators[\\\\/]\\ze.","")')
    call map(generators, 's:sub(v:val,"[\\\\/][^\\\\/]*_generator\.rb$","")')
    call map(generators, 'tr(v:val, "/", ":")')
    let builtin += map(filter(copy(generators), 'v:val =~# "^rails:"'), 'v:val[6:-1]')
    call filter(generators,'v:val !~# "^rails:"')
    call self.cache.set('generators',s:uniq(builtin + generators))
  endif
  return self.cache.get('generators')
endfunction

function! s:Rails(bang, count, arg) abort
  let use_rake = 0
  if !empty(a:arg)
    let str = a:arg
    let native = '\v^%(application|benchmarker|console|dbconsole|destroy|generate|new|plugin|profiler|runner|server|version|[cgst]|db)>'
    if !rails#app().has('rails3')
      let use_rake = !rails#app().has_file('script/' . matchstr(str, '\S\+'))
    elseif str !~# '^-' && str !~# native
      let use_rake = 1
    endif
  else
    let str = rails#buffer().default_rake_task(a:count)
    if str ==# '--tasks'
      let str = ''
    else
      let use_rake = 1
    endif
  endif
  if str =~# '^\%(c\|console\|db\|dbconsole\|s\|server\)\S\@!' && str !~# ' -d\| --daemon\| --help'
    return rails#app().start_rails_command(str, a:bang)
  else
    let [mp, efm, cc] = [&l:mp, &l:efm, get(b:, 'current_compiler', '')]
    try
      compiler rails
      if use_rake && !rails#app().has_rails5()
        let &l:makeprg = rails#app().rake_command()
      else
        let str = s:rake2rails(str)
        let &l:makeprg = rails#app().prepare_rails_command('$*')
      endif
      let &l:errorformat .= ',chdir '.escape(rails#app().path(), ',')
      call s:make(a:bang, str)
    finally
      let [&l:mp, &l:efm, b:current_compiler] = [mp, efm, cc]
      if empty(cc) | unlet! b:current_compiler | endif
    endtry
    return ''
  endif
endfunction

function! s:readable_runner_command(bang, count, arg) dict abort
  let old_makeprg = &l:makeprg
  let old_errorformat = &l:errorformat
  let old_compiler = get(b:, 'current_compiler', '')
  try
    if !empty(a:arg)
      let arg = a:arg
    elseif a:count
      let arg = self.name()
    else
      let arg = self.test_file()
      if empty(arg)
        let arg = self.name()
      endif
    endif

    let extra = ''
    if a:count > 0
      let extra = ':'.a:count
    endif

    let file = arg ==# self.name() ? self : self.app().file(arg)
    if arg =~# '^test/.*_test\.rb$'
      let compiler = 'rubyunit'
      if a:count > 0
        let method = file.last_method(a:count)
        if method =~ '^test_'
          let extra = ' -n'.method
        else
          let extra = ''
        endif
      endif
    elseif arg =~# '^spec\%(/.*\%(_spec\.rb\|\.feature\)\)\=$'
      let compiler = 'rspec'
    elseif arg =~# '^features\%(/.*\.feature\)\=$'
      let compiler = 'cucumber'
    else
      let compiler = 'ruby'
    endif

    let compiler = get(file.projected('railsRunner') + file.projected('compiler'), 0, compiler)
    if compiler ==# 'testrb' || compiler ==# 'minitest'
      let compiler = 'rubyunit'
    elseif empty(findfile('compiler/'.compiler.'.vim', escape(&rtp, ' ')))
      let compiler = 'ruby'
    endif

    execute 'compiler' compiler

    if compiler ==# 'ruby'
      let &l:makeprg = self.app().prepare_rails_command('runner')
      let extra = ''
    elseif &makeprg =~# '^\%(testrb\|rspec\|cucumber\)\>' && self.app().has_zeus()
      let &l:makeprg = 'zeus ' . &l:makeprg
    elseif compiler ==# 'rubyunit'
      let &l:makeprg = 'ruby -Itest'
    elseif filereadable(self.app().real('bin/' . &l:makeprg))
      let &l:makeprg = self.app().ruby_script_command('bin/' . &l:makeprg)
    elseif &l:makeprg !~# '^bundle\>' && self.app().has('bundler')
      let &l:makeprg = 'bundle exec ' . &l:makeprg
    endif

    let &l:errorformat .= ',chdir '.escape(self.app().path(), ',')

    call s:make(a:bang, arg . extra)
    return ''

  finally
    let &l:errorformat = old_errorformat
    let &l:makeprg = old_makeprg
    let b:current_compiler = old_compiler
    if empty(b:current_compiler)
      unlet b:current_compiler
    endif
  endtry
  return ''
endfunction

call s:add_methods('readable', ['runner_command'])

function! s:app_output_command(count, code) dict
  let str = self.prepare_rails_command('runner '.s:rquote(a:code))
  call s:push_chdir(1)
  try
    let res = s:sub(system(str),'\n$','')
  finally
    call s:pop_command()
  endtry
  if a:count < 0
    echo res
  else
    exe a:count.'put =res'
  endif
  return ''
endfunction

function! rails#get_binding_for(pid) abort
  if empty(a:pid)
    return ''
  endif
  if has('win32')
    let output = system('netstat -anop tcp')
    let binding = matchstr(output, '\n\s*TCP\s\+\zs\S\+\ze\s\+\S\+\s\+LISTENING\s\+'.a:pid.'\>')
    return s:sub(binding, '^([^[]*:.*):', '[\1]:')
  endif
  if executable('lsof')
    let lsof = 'lsof'
  elseif executable('/usr/sbin/lsof')
    let lsof = '/usr/sbin/lsof'
  endif
  if exists('lsof')
    let output = system(lsof.' -anP -i4tcp -sTCP:LISTEN -p'.a:pid)
    let binding = matchstr(output, '\S\+:\d\+\ze\s\+(LISTEN)\n')
    let binding = s:sub(binding, '^\*', '0.0.0.0')
    if empty(binding)
      let output = system(lsof.' -anP -i6tcp -sTCP:LISTEN -p'.a:pid)
      let binding = matchstr(output, '\S\+:\d\+\ze\s\+(LISTEN)\n')
      let binding = s:sub(binding, '^\*', '[::]')
    endif
    return binding
  endif
  if executable('netstat')
    let output = system('netstat -antp')
    let binding = matchstr(output, '\S\+:\d\+\ze\s\+\S\+\s\+LISTEN\s\+'.a:pid.'/')
    return s:sub(binding, '^([^[]*:.*):', '[\1]:')
  endif
  return ''
endfunction

function! s:app_server_command(kill, bg, arg) dict abort
  let arg = empty(a:arg) ? '' : ' '.a:arg
  let flags = ' -d\| --daemon\| --help'
  if a:kill || a:arg =~# '^ *[!-]$' || (a:bg && arg =~# flags)
    let pid = self.server_pid()
    if pid
      echo "Killing server with pid ".pid
      if !has("win32")
        call system("ruby -e 'Process.kill(:TERM,".pid.")'")
        sleep 100m
      endif
      call system("ruby -e 'Process.kill(9,".pid.")'")
      sleep 100m
    else
      echo "No server running"
    endif
    if a:arg =~# '^ *[-!]$'
      return
    endif
  endif
  if exists(':Start') == 0 && !has('win32') && arg !~# flags
    let arg .= ' -d'
  endif
  if a:arg =~# flags
    call self.execute_rails_command('server '.a:arg)
  else
    call self.start_rails_command('server '.a:arg, a:bg)
  endif
  return ''
endfunction

function! s:color_efm(pre, before, after)
   return a:pre . '%\e%\S%\+  %#' . a:before . '%\e[0m  %#' . a:after . ',' .
         \ a:pre . '%\s %#'.a:before.'  %#'.a:after . ','
endfunction

let s:efm_generate =
      \ s:color_efm('%-G', 'invoke', '%.%#') .
      \ s:color_efm('%-G', 'conflict', '%.%#') .
      \ s:color_efm('%-G', 'run', '%.%#') .
      \ s:color_efm('%-G', 'route', '%.%#') .
      \ s:color_efm('%-G', '%\w%\+', ' ') .
      \ '%-G %#Overwrite%.%#"h"%.%#,' .
      \ ' %#Overwrite%.%#%\S%\+  %#%m%\e[0m  %#%f,' .
      \ s:color_efm('', '%m%\>', '%f') .
      \ '%-G%.%#'

function! s:app_generator_command(bang, mods, ...) dict abort
  call self.cache.clear('user_classes')
  call self.cache.clear('features')
  let cmd = join(map(copy(a:000),'s:rquote(v:val)'),' ')
  let old_makeprg = &l:makeprg
  let old_errorformat = &l:errorformat
  try
    let &l:makeprg = self.prepare_rails_command(cmd)
    let &l:errorformat = s:efm_generate . ',chdir '.escape(self.path(), ',')
    call s:push_chdir(1)
    noautocmd make!
  finally
    call s:pop_command()
    let &l:errorformat = old_errorformat
    let &l:makeprg = old_makeprg
  endtry
  if a:bang || empty(getqflist())
    return ''
  else
    return s:mods(a:mods) . ' cfirst'
  endif
endfunction

call s:add_methods('app', ['generators','output_command','server_command','generator_command'])

function! rails#complete_rails(ArgLead, CmdLine, P, ...) abort
  if a:0
    let app = a:1
  else
    let root = s:efm_dir()
    if empty(root)
      let manifest = findfile('config/environment.rb', escape(getcwd(), ' ,;').';')
      let root = empty(manifest) ? '' : fnamemodify(manifest, ':p:h:h')
    endif
    let app = empty(root) ? {} : rails#app(root)
  endif
  let cmd = s:sub(a:CmdLine,'^\u\w*\s+','')
  if cmd =~# '^new\s\+'
    return split(glob(a:ArgLead.'*/'), "\n")
  elseif empty(app)
    return s:completion_filter(['new'], a:ArgLead)
  elseif cmd =~# '^$\|^\w\S*$'
    let cmds = ['generate', 'console', 'server', 'dbconsole', 'destroy', 'plugin', 'runner']
    call extend(cmds, app.rake_tasks())
    call sort(cmds)
    return s:completion_filter(cmds, a:ArgLead)
  elseif cmd =~# '^\%([rt]\|runner\|test\|test:db\)\s\+'
    return s:completion_filter(app.relglob('', s:fuzzyglob(a:ArgLead)), a:ArgLead)
  elseif cmd =~# '^\%([gd]\|generate\|destroy\)\s\+'.a:ArgLead.'$'
    return s:completion_filter(app.generators(),a:ArgLead)
  elseif cmd =~# '^\%([gd]\|generate\|destroy\)\s\+\w\+\s\+'.a:ArgLead.'$'
    let target = matchstr(cmd,'^\w\+\s\+\%(\w\+:\)\=\zs\w\+\ze\s\+')
    if target =~# '^\w*controller$'
      return filter(s:controllerList(a:ArgLead,"",""),'v:val !=# "application"')
    elseif target ==# 'generator'
      return s:completion_filter(map(app.relglob('lib/generators/','*'),'s:sub(v:val,"/$","")'), a:ArgLead)
    elseif target ==# 'helper'
      return s:autocamelize(app.relglob('app/helpers/','**/*','_helper.rb'),a:ArgLead)
    elseif target ==# 'integration_test' || target ==# 'integration_spec' || target ==# 'feature'
      return s:autocamelize(
            \ app.relglob('test/integration/','**/*','_test.rb') +
            \ app.relglob('spec/features/', '**/*', '_spec.rb') +
            \ app.relglob('spec/requests/', '**/*', '_spec.rb') +
            \ app.relglob('features/', '**/*', '.feature'), a:ArgLead)
    elseif target ==# 'migration' || target ==# 'session_migration'
      return s:migrationList(a:ArgLead,"","")
    elseif target ==# 'mailer'
      return s:completion_filter(app.relglob("app/mailers/","**/*",".rb"),a:ArgLead)
    elseif target =~# '^\w*\%(model\|resource\)$' || target =~# '\w*scaffold\%(_controller\)\=$'
      return s:completion_filter(app.relglob('app/models/','**/*','.rb'), a:ArgLead)
    else
      return []
    endif
  elseif cmd =~# '^\%([gd]\|generate\|destroy\)\s\+scaffold\s\+\w\+\s\+'.a:ArgLead.'$'
    return filter(s:controllerList(a:ArgLead,"",""),'v:val !=# "application"')
    return s:completion_filter(app.environments())
  elseif cmd =~# '^\%(c\|console\)\s\+\(--\=\w\+\s\+\)\='.a:ArgLead."$"
    return s:completion_filter(app.environments()+["-s","--sandbox"],a:ArgLead)
  elseif cmd =~# '^\%(db\|dbconsole\)\s\+\(--\=\w\+\s\+\)\='.a:ArgLead."$"
    return s:completion_filter(app.environments()+["-p","--include-password"],a:ArgLead)
  elseif cmd =~# '^\%(s\|server\)\s\+.*-e\s\+'.a:ArgLead."$"
    return s:completion_filter(app.environments(),a:ArgLead)
  elseif cmd =~# '^\%(s\|server\)\s\+'
    if a:ArgLead =~# '^--environment='
      return s:completion_filter(map(copy(app.environments()),'"--environment=".v:val'),a:ArgLead)
    else
      return filter(["-p","-b","-c","-d","-u","-e","-P","-h","--port=","--binding=","--config=","--daemon","--debugger","--environment=","--pid=","--help"],'s:startswith(v:val,a:ArgLead)')
    endif
  endif
  return []
endfunction

function! s:CustomComplete(A,L,P,cmd) abort
  let L = "Rscript ".a:cmd." ".s:sub(a:L,'^\h\w*\s+','')
  let P = a:P - strlen(a:L) + strlen(L)
  return rails#complete_rails(a:A, L, P, rails#app())
endfunction

function! s:Complete_server(A,L,P) abort
  return s:CustomComplete(a:A,a:L,a:P,"server")
endfunction

function! s:Complete_console(A,L,P) abort
  return s:CustomComplete(a:A,a:L,a:P,"console")
endfunction

function! s:Complete_generate(A,L,P) abort
  return s:CustomComplete(a:A,a:L,a:P,"generate")
endfunction

function! s:Complete_destroy(A,L,P) abort
  return s:CustomComplete(a:A,a:L,a:P,"destroy")
endfunction

function! s:Complete_ruby(A,L,P) abort
  return s:completion_filter(rails#app().user_classes()+["ActiveRecord::Base"],a:A)
endfunction

" }}}1
" Navigation {{{1

function! s:BufNavCommands()
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_alternate A   exe s:Alternate('<mods> E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_alternate AE  exe s:Alternate('<mods> E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_alternate AS  exe s:Alternate('<mods> S<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_alternate AV  exe s:Alternate('<mods> V<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_alternate AT  exe s:Alternate('<mods> T<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_edit      AD  exe s:Alternate('<mods> D<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_edit      AR  exe s:Alternate('<mods> D<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related   R   exe   s:Related('<mods> E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related   RE  exe   s:Related('<mods> E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related   RS  exe   s:Related('<mods> S<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related   RV  exe   s:Related('<mods> V<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related   RT  exe   s:Related('<mods> T<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_edit      RD  exe   s:Related('<mods> D<bang>',<line1>,<line2>,<count>,<f-args>)
endfunction

function! s:jumpargs(file, jump) abort
  let file = fnameescape(a:file)
  if empty(a:jump)
    return file
  elseif a:jump ==# '!'
    return '+AD ' . file
  elseif a:jump =~# '^\d\+$'
    return '+' . a:jump . ' ' . file
  else
    return '+A#' . a:jump . ' ' . file
  endif
endfunction

function! s:jump(def, ...) abort
  let def = s:sub(a:def,'^[#:]','')
  let edit = s:editcmdfor(a:0 ? a:1 : '')
  if edit !~# 'edit'
    exe edit
  endif
  if def =~ '^\d\+$'
    exe def
  elseif def !~# '^$\|^!'
    let ext = matchstr(def,'\.\zs.*')
    let def = matchstr(def,'[^.]*')
    let include = &l:include
    try
      setlocal include=
      exe 'djump' def
    catch /^Vim(djump):E387/
    catch
      let error = 1
    finally
      let &l:include = include
    endtry
    if !empty(ext) && expand('%:e') ==# 'rb' && !exists('error')
      let rpat = '\C^\s*\%(mail\>.*\|respond_to\)\s*\%(\<do\|{\)\s*|\zs\h\k*\ze|'
      let end = s:endof(line('.'))
      let rline = search(rpat,'',end)
      if rline > 0
        let variable = matchstr(getline(rline),rpat)
        let success = search('\C^\s*'.variable.'\s*\.\s*\zs'.ext.'\>','',end)
        if !success
          try
            setlocal include=
            exe 'djump' def
          catch
          finally
            let &l:include = include
          endtry
        endif
      endif
    endif
  endif
  return ''
endfunction

function! s:fuzzyglob(arg) abort
  return s:gsub(s:gsub(a:arg,'[^/.]','[&]*'),'%(/|^)\.@!|\.','&*')
endfunction

function! s:Complete_edit(ArgLead, CmdLine, CursorPos) abort
  return s:completion_filter(rails#app().relglob("",s:fuzzyglob(a:ArgLead)),a:ArgLead)
endfunction

function! s:Complete_cd(ArgLead, CmdLine, CursorPos) abort
  let all = rails#app().relglob("",a:ArgLead."*")
  call filter(all,'v:val =~ "/$"')
  return filter(all,'s:startswith(v:val,a:ArgLead)')
endfunction

function! s:match_cursor(pat) abort
  let line = getline(".")
  let lastend = 0
  while lastend >= 0
    let beg = match(line,'\C'.a:pat,lastend)
    let end = matchend(line,'\C'.a:pat,lastend)
    if beg < col(".") && end >= col(".")
      return matchstr(line,'\C'.a:pat,lastend)
    endif
    let lastend = end
  endwhile
  return ""
endfunction

function! s:match_it(pat, repl) abort
  let res = s:match_cursor(a:pat)
  if res != ""
    return substitute(res,'\C'.a:pat,a:repl,'')
  else
    return ""
  endif
endfunction

function! s:match_method(func, ...) abort
  let l = ''
  let r = ''
  if &filetype =~# '\<eruby\>'
    let l = '\s*\%(<%\)\=[=-]\='
    let r = '\s*\%(-\=%>\s*\)\='
  elseif &filetype =~# '\<haml\>'
    let l = '\s*[=-]'
  endif
  let result = s:match_it(l.'\s*\<\%('.a:func.'\)\s*(\=\s*\(:\=[''"@]\=\f\+\)\>[''"]\='.r, '\1')
  return a:0 ? result : substitute(result, '^:\=[''"@]\=', '', '')
endfunction

function! s:match_symbol(sym) abort
  return s:match_it('\s*\%(:\%('.a:sym.'\)\s*=>\|\<'.a:sym.':\)\s*(\=\s*[@:'."'".'"]\(\f\+\)\>.\=', '\1')
endfunction

function! s:match_partial(func) abort
  let res = s:match_method(a:func, '\1', 1)
  if empty(res)
    return ''
  elseif res =~# '^\w\+\%(\.\w\+\)\=$'
    let res = rails#singularize(s:sub(res, '^\w*\.', ''))
    return s:findview(rails#pluralize(res).'/_'.res)
  else
    return s:findview(s:sub(s:sub(res, '^:=[''"@]=', ''), '[^/]*$', '_&'))
  endif
endfunction

function! s:suffixes(type) abort
  if a:type =~# '^stylesheets\=$\|^css$'
    let exts = ['css', 'scss', 'css.scss', 'sass', 'css.sass']
    call extend(exts, map(copy(exts), 'v:val.".erb"'))
  elseif a:type =~# '^javascripts\=$\|^js$'
    let exts = ['js', 'coffee', 'js.coffee', 'es6']
    call extend(exts, map(copy(exts), 'v:val.".erb"'))
    call extend(exts, ['ejs', 'eco', 'jst', 'jst.ejs', 'jst.eco'])
  else
    return []
  endif
  let suffixes = map(copy(exts), '".".v:val')
  call extend(suffixes, map(copy(suffixes), '"/index".v:val'))
  return s:uniq(suffixes)
endfunction

function! s:findasset(path, dir) abort
  let path = a:path
  if path =~# '^\.\.\=/'
    let path = expand('%:p:h:h') . '/' . path[3:-1]
  endif
  let suffixes = s:suffixes(a:dir)
  let asset = s:resolve_asset(path, suffixes)
  if len(asset)
    return asset
  endif
  if path ==# a:path
    if empty(a:dir)
      return ''
    endif
    if a:dir ==# 'stylesheets' && rails#app().has('sass')
      let sass = rails#app().path('public/stylesheets/sass/' . path)
      if s:filereadable(sass)
        return sass
      elseif s:filereadable(sass.'.sass')
        return sass.'.sass'
      elseif s:filereadable(sass.'.scss')
        return sass.'.scss'
      endif
    endif
    let public = rails#app().path('public/' . a:dir . '/' . path)
    let post = get(suffixes, 0, '')
    if s:filereadable(public)
      return public
    elseif s:filereadable(public . post)
      return public . post
    elseif rails#app().has_path('app/assets/' . a:dir) || !rails#app().has_path('public/' . a:dir)
      let path = rails#app().path('app/assets/' . a:dir . '/' . path)
    else
      let path = public
    endif
  endif
  if !empty(getftype(path)) || path =~# '\.\w\+$'
    return path
  endif
  return path . post
endfunction

function! s:cfile_delegate(expr) abort
  let expr = empty(a:expr) ? matchstr(&includeexpr, '.*\<v:fname\>.*') : a:expr
  if empty(expr)
    let expr = 'v:fname'
  endif
  let expr = substitute(expr, '\<v:fname\>', 'expand("<cfile>")', 'g')
  return expr
endfunction

function! s:sprockets_cfile() abort
  let dir = ''

  if &sua =~# '\.js\>'
    let dir = 'javascripts'
  elseif &sua =~# '\.css\>'
    let dir = 'stylesheets'

    let asset = ''
    let sssuf = s:suffixes('stylesheets')
    let res = s:match_it('\%(^\s*[[:alnum:]-]\+:\s\+\)\=\<[[:alnum:]-]\+-\%(path\|url\)(["'']\=\([^"''() ]*\)', '\1')
    if !empty(res)
      let asset = s:resolve_asset(res)
    endif
    let res = s:match_it('\%(^\s*[[:alnum:]-]\+:\s\+\)\=\<stylesheet-\%(path\|url\)(["'']\=\([^"''() ]*\)', '\1')
    if !empty(res)
      let asset = s:resolve_asset(res, sssuf)
    endif
    let res = s:match_it('\%(^\s*[[:alnum:]-]\+:\s\+\)\=\<javascript-\%(path\|url\)(["'']\=\([^"''() ]*\)', '\1')
    if !empty(res)
      let asset = s:resolve_asset(res, s:suffixes('javascripts'))
    endif
    if !empty(asset)
      return asset
    endif
    let res = s:match_it('^\s*@import\s*\%(url(\)\=["'']\=\([^"''() ]*\)', '\1')
    if !empty(res)
      let base = expand('%:p:h')
      let rel = s:sub(res, '\ze[^/]*$', '_')
      let sssuf = s:suffixes('stylesheets')
      for ext in [''] + sssuf
        for name in [res.ext, rel.ext]
          if s:filereadable(base.'/'.name)
            return base.'/'.name
          endif
        endfor
      endfor
      let asset = s:resolve_asset(res, sssuf)
      if empty(asset) && expand('%:e') =~# '^s[ac]ss$'
        let asset = s:resolve_asset(rel, sssuf)
      endif
      return empty(asset) ? 'app/assets/stylesheets/'.res : asset
    endif
  endif

  let res = s:match_it('^\s*\%(//\|[*#]\)=\s*\%(link\|require\|depend_on\|stub\)\w*\s*["'']\=\([^"'' ]*\)', '\1')
  if !empty(res) && exists('l:dir')
    let asset = s:resolve_asset(res, dir)
    return empty(asset) ? res : asset
  endif
  return ''
endfunction

function! rails#sprockets_cfile(...) abort
  let file = s:dot_relative(s:sprockets_cfile())
  if empty(file)
    return eval(s:cfile_delegate(a:0 ? a:1 : ''))
  endif
  let escaped = s:fnameescape(file)
  if file ==# escaped
    return file
  else
    return '+ '.escaped
  endif
endfunction

function! s:ruby_cfile() abort
  let buffer = rails#buffer()

  let res = s:match_it('\v\s*<require\s*\(=\s*File.expand_path\([''"]../(\f+)[''"],\s*__FILE__\s*\)',expand('%:p:h').'/\1')
  if len(res)|return s:simplify(res.(res !~ '\.[^\/.]\+$' ? '.rb' : ''))|endif

  let res = s:match_it('\v<File.expand_path\([''"]../(\f+)[''"],\s*__FILE__\s*\)',expand('%:p:h').'/\1')
  if len(res)|return s:simplify(res)|endif

  let res = s:match_it('\v\s*<require\s*\(=\s*File.dirname\(__FILE__\)\s*\+\s*[:''"](\f+)>.=',expand('%:p:h').'/\1')
  if len(res)|return s:simplify(res.(res !~ '\.[^\/.]\+$' ? '.rb' : ''))|endif

  let res = s:match_it('\v<File.dirname\(__FILE__\)\s*\+\s*[:''"](\f+)>[''"]=',expand('%:p:h').'\1')
  if len(res)|return s:simplify(res)|endif

  let res = s:match_it('\v\s*<%(include|extend)\(=\s*<([[:alnum:]_:]+)>','\1')
  if len(res)|return rails#underscore(res, 1).".rb"|endif

  let res = s:match_method('require')
  if len(res)|return res.(res !~ '\.[^\/.]\+$' ? '.rb' : '')|endif

  if !empty(s:match_method('\w\+'))
    let class = s:match_it('^[^;#]*,\s*\%(:class_name\s*=>\|class_name:\)\s*["'':]\=\([[:alnum:]_:]\+\)','\1')
    if len(class)|return rails#underscore(class, 1).".rb"|endif
  endif

  let res = s:match_method('belongs_to\|has_one\|embedded_in\|embeds_one\|composed_of\|validates_associated\|scaffold')
  if len(res)|return res.'.rb'|endif

  let res = s:match_method('has_many\|has_and_belongs_to_many\|embeds_many\|accepts_nested_attributes_for\|expose')
  if len(res)|return rails#singularize(res).'.rb'|endif

  let res = s:match_method('create_table\|change_table\|drop_table\|rename_table\|\%(add\|remove\)_\%(column\|index\|timestamps\|reference\|belongs_to\)\|rename_column\|remove_columns\|rename_index')
  if len(res)|return rails#singularize(res).'.rb'|endif

  let res = s:match_symbol('through')
  if len(res)|return rails#singularize(res).".rb"|endif

  let res = s:match_method('fixtures')
  if len(res)|return 'fixtures/'.res.'.yml'|endif

  let res = s:match_method('fixture_file_upload')
  if len(res)|return 'fixtures/'.res|endif

  let res = s:match_method('file_fixture')
  if len(res)|return 'fixtures/files/'.res|endif

  let res = s:match_method('\%(\w\+\.\)\=resources')
  if len(res)|return res.'_controller.rb'|endif

  let res = s:match_method('\%(\w\+\.\)\=resource')
  if len(res)|return rails#pluralize(res)."_controller.rb"|endif

  let res = s:match_symbol('to')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  let res = s:match_method('root\s*\%(:to\s*=>\|\<to:\)\s*')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  let res = s:match_method('\%(match\|get\|put\|patch\|post\|delete\|redirect\)\s*(\=\s*[:''"][^''"]*[''"]\=\s*\%(\%(,\s*:to\s*\)\==>\|,\s*to:\)\s*')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  let res = s:match_method('layout')
  if len(res)|return s:findlayout(res)|endif

  let res = s:match_method('helper')
  if len(res)|return res.'_helper.rb'|endif

  let res = s:match_symbol('controller')
  if len(res)|return s:sub(res, '^/', '').'_controller.rb'|endif

  let res = s:match_symbol('action')
  if len(res)|return s:findview(res)|endif

  let res = s:match_symbol('template')
  if len(res)|return s:findview(res)|endif

  let res = s:sub(s:sub(s:match_symbol('partial'),'^/',''),'[^/]+$','_&')
  if len(res)|return s:findview(res)|endif

  let res = s:sub(s:sub(s:match_method('(\=\s*\%(:partial\s\+=>\|partial:\s*\|json.partial!\)\s*'),'^/',''),'[^/]+$','_&')
  if len(res)|return s:findview(res)|endif

  let res = s:match_partial('render\%(_to_string\)\=\s*(\=\s*\%(:partial\s\+=>\|partial:\)\s*')
  if len(res)|return res|endif

  let res = s:match_method('render\>\s*\%(:\%(template\|action\)\s\+=>\|template:\|action:\)\s*')
  if len(res)|return s:findview(res)|endif

  let contr = matchstr(expand('%:p'), '.*[\/]app[\/]\%(controllers[\/].*\ze_controller\|mailers[\/].*\ze\|models[\/].*_mailer\ze\)\.rb$')
  if len(contr)
    let res = s:sub(s:match_symbol('layout'),'^/','')
    if len(res)|return s:findlayout(res)|endif
    let raw = s:sub(s:match_method('render\s*(\=\s*\%(:layout\s\+=>\|layout:\)\s*',1),'^/','')
    if len(res)|return s:findview(res)|endif
    let res = s:sub(s:match_method('render'),'^/','')
    if len(res)|return s:findview(res)|endif

    let viewpath = substitute(contr, '\([\/]\)app\zs[\/]\%(controllers\|mailers\|models\)\([\/].*\)', '\1views\2\1', '')
    let view = s:match_it('\s*\<def\s\+\(\k\+\)\>(\=','\1')
    if len(viewpath) && len(view)
      let res = s:glob(viewpath . view . '.html.*')
      if len(res)|return res[0]|endif
      let res = s:glob(viewpath . view . '.*')
      if len(res)|return res[0]|endif
      return substitute(viewpath, '.*[\/]app[\/]views[\/]', '', '') . view . '.html'
    endif
  else
    let res = s:sub(s:match_symbol('layout'),'^/','')
    if len(res)|return s:findview(s:sub(res, '[^/]+$', '_&'))|endif
    let raw = s:sub(s:match_method('render\s*(\=\s*\%(:layout\s\+=>\|layout:\)\s*',1),'^/','')
    if len(res)|return s:findview(s:sub(res, '[^/]+$', '_&'))|endif
    let res = s:match_partial('render')
    if len(res)|return res|endif
  endif

  let res = s:match_method('redirect_to\s*(\=\s*\%\(:action\s\+=>\|\<action:\)\s*')
  if len(res)|return res|endif

  let res = s:match_method('image[_-]\%(\|path\|url\)\|\%(path\|url\)_to_image')
  if len(res)
    return s:findasset(res, 'images')
  endif

  let res = s:match_method('stylesheet[_-]\%(link_tag\|path\|url\)\|\%(path\|url\)_to_stylesheet')
  if len(res)
    return s:findasset(res, 'stylesheets')
  endif

  let res = s:sub(s:match_method('javascript_\%(include_tag\|path\|url\)\|\%(path\|url\)_to_javascript'),'/defaults>','/application')
  if len(res)
    return s:findasset(res, 'javascripts')
  endif

  for [type, suf] in [['javascript', '.js'], ['stylesheet', '.css'], ['asset', '']]
    let res = s:match_method(type.'_pack_\%(path\|tag\)')
    let appdir = matchstr(expand('%:p'), '.*[\/]app[\/]\ze\%(views\|helpers\)[\/]')
    if empty(appdir) && s:active()
      let appdir = rails#app().path('app/')
    endif
    if len(res) && len(appdir)
      let name = res . suf
      let suffixes = rails#pack_suffixes(matchstr(name, '\.\zs\w\+$'))
      call extend(suffixes, map(copy(suffixes), '"/index".v:val'))
      let dir = appdir . 'javascript' . appdir[-1:-1] . 'packs' . appdir[-1:-1]
      if len(suffixes)
        let base = dir . substitute(name, '\.\w\+$', '', '')
        for suffix in [''] + suffixes
          if s:filereadable(base . suffix)
            return base . suffix
          endif
        endfor
        return dir . name
      endif
    endif
  endfor

  let decl = matchlist(getline('.'),
        \ '^\(\s*\)\(\w\+\)\>\%\(\s\+\|\s*(\s*\):\=\([''"]\=\)\(\%(\w\|::\)\+\)\3')
  if len(decl) && len(decl[0]) >= col('.')
    let declid = synID(line('.'), 1+len(decl[1]), 1)
    let declbase = rails#underscore(decl[4], 1)
    if declid ==# hlID('rubyEntities')
      return rails#singularize(declbase) . '.rb'
    elseif declid ==# hlID('rubyEntity') || decl[4] =~# '\u'
      return declbase . '.rb'
    elseif index([hlID('rubyMacro'), hlID('rubyAttribute')], declid) >= 0
      return rails#singularize(declbase) . '.rb'
    endif
  endif

  let synid = synID(line('.'), col('.'), 1)
  let old_isfname = &isfname
  try
    if synid == hlID('rubyString')
      set isfname+=:
      let cfile = expand("<cfile>")
    else
      set isfname=@,48-57,/,-,_,:,#
      let cfile = expand("<cfile>")
      if cfile !~# '\u\|/'
        let cfile = s:sub(cfile, '_attributes$', '')
        let cfile = rails#singularize(cfile)
        let cfile = s:sub(cfile, '_ids=$', '')
      endif
    endif
  finally
    let &isfname = old_isfname
  endtry
  let cfile = s:sub(cfile, '^:=[:@]', '')
  let cfile = s:sub(cfile, ':0x\x+$', '') " For #<Object:0x...> style output
  if cfile =~# '^\l\w*#\w\+$'
    let cfile = s:sub(cfile, '#', '_controller.rb#')
  elseif cfile =~# '\u'
    let cfile = rails#underscore(cfile, 1) . '.rb'
  elseif cfile =~# '^\w*_\%(path\|url\)$' && synid != hlID('rubyString')
    let route = s:gsub(cfile, '^hash_for_|_%(path|url)$', '')
    let cfile = s:active() ? rails#app().named_route_file(route) : ''
    if empty(cfile)
      let cfile = s:sub(route, '^formatted_', '')
      if cfile =~# '^\%(new\|edit\)_'
        let cfile = s:sub(rails#pluralize(cfile), '^(new|edit)_(.*)', '\2_controller.rb#\1')
      elseif cfile ==# rails#singularize(cfile)
        let cfile = rails#pluralize(cfile).'_controller.rb#show'
      else
        let cfile = cfile.'_controller.rb#index'
      endif
    endif
  elseif cfile !~# '\.'
    let cfile .= '.rb'
  endif
  return cfile
endfunction

function! rails#ruby_cfile(...) abort
  let cfile = s:find('find', s:ruby_cfile())[5:-1]
  return empty(cfile) ? (a:0 ? eval(a:1) : expand('<cfile>')) : cfile
endfunction

function! s:app_named_route_file(route_name) dict abort
  for route in self.routes()
    if get(route, 'name', '') ==# a:route_name && route.handler =~# '#'
      return s:sub(route.handler, '#', '_controller.rb#')
    endif
  endfor
  return ""
endfunction

function! s:app_routes() dict abort
  if self.cache.needs('routes')
    let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : 'cd'
    let cwd = getcwd()
    let routes = []
    let paths = {}
    let binding = self.server_binding()
    if len(binding) && len(s:webcat())
      let html = system(s:webcat() . ' ' . shellescape('http://' . binding . '/rails/info/routes'))
      for line in split(matchstr(html, '.*<tbody>\zs.*\ze</tbody>'), "\n")
        let val = matchstr(line, '\C<td data-route-name=''\zs[^'']*''\ze>')
        if len(val)
          if len(routes) && len(routes[-1]) < 4
            call remove(routes, -1)
          endif
          call add(routes, {'name': val[0:-2]})
        endif
        if empty(routes)
          continue
        endif
        let val = matchstr(line, '\C<td data-route-path=''\zs[^'']*\ze''>')
        if len(val)
          let routes[-1].path = val
          if empty(routes[-1].name)
            let routes[-1].name = get(paths, val, '')
          else
            let paths[val] = routes[-1].name
          endif
        endif
        let val = matchstr(line, '\C^\s*\zs[[:upper:]|]\+')
        if len(val)
          let routes[-1].method = val
        endif
        let val = matchstr(line, '\C<p>\zs\%(redirect(.\{-\})\|\S\+#[^ #<]\+\)')
        if len(val)
          let routes[-1].handler = val
        endif
      endfor
    endif
    if empty(routes)
      try
        execute cd fnameescape(self.real())
        let output = system(self.rake_command().' routes')
      finally
        execute cd fnameescape(cwd)
      endtry
      for line in split(output, "\n")
        let matches = matchlist(line, '\C^ *\(\l\w*\|\) \{-\}\([A-Z|]*\) \+\(\S\+\) \+\(redirect(.\{-\})\|[[:alnum:]_/:]\+#:\=\w\+\)\%( {.*\)\=$')
        if !empty(matches)
          let [_, name, method, path, handler; __] = matches
          if !empty(name)
            let paths[path] = name
          else
            let name = get(paths, path, '')
          endif
          call add(routes, {'method': method, 'path': path, 'handler': handler, 'name': name})
        endif
      endfor
    endif
    call self.cache.set('routes', routes)
  endif

  return self.cache.get('routes')
endfunction

call s:add_methods('app', ['routes', 'named_route_file'])

" }}}1
" Projection Commands {{{1

function! s:app_commands() dict abort
  let commands = {}
  let all = self.projections()
  for pattern in sort(keys(all), function('rails#lencmp'))
    let projection = all[pattern]
    for name in s:split(get(projection, 'command', get(projection, 'type', get(projection, 'name', ''))))
      let command = {
            \ 'pattern': pattern,
            \ 'affinity': get(projection, 'affinity', '')}
      if !has_key(commands, name)
        let commands[name] = []
      endif
      call insert(commands[name], command)
    endfor
  endfor
  call filter(commands, '!empty(v:val)')
  return commands
endfunction

call s:add_methods('app', ['commands'])

function! s:addfilecmds(type, defer) abort
  let l = s:sub(a:type,'^.','\l&')
  let cplt = " -complete=customlist,".s:sid.l."List"
  if a:defer && exists(':E' . l) == 2
    return
  endif
  for prefix in ['E', 'S', 'V', 'T', 'D']
    exe "command! -buffer -bar ".(prefix =~# 'D' ? '-range=0 ' : '')."-nargs=*".cplt." ".prefix.l." :execute s:".l.'Edit("<mods> '.(prefix =~# 'D' ? '<line1>' : '').s:sub(prefix, '^R', '').'<bang>",<f-args>)'
  endfor
endfunction

function! s:BufProjectionCommands() abort
  let deepest = get(sort(keys(get(b:, 'projectionist', {})), 'rails#lencmp'), -1, '')
  let defer = len(deepest) > len(rails#app().path())
  call s:addfilecmds("view", defer)
  call s:addfilecmds("migration", defer)
  call s:addfilecmds("schema", defer)
  call s:addfilecmds("layout", defer)
  call s:addfilecmds("fixtures", defer)
  call s:addfilecmds("locale", defer)
  if rails#app().has('spec')
    call s:addfilecmds("spec", defer)
  endif
  call s:addfilecmds("stylesheet", defer)
  call s:addfilecmds("javascript", defer)
  for [name, command] in items(rails#app().commands())
    call s:define_navcommand(name, command)
  endfor
endfunction

function! s:completion_filter(results, A, ...) abort
  if exists('*projectionist#completion_filter')
    return projectionist#completion_filter(a:results, a:A, a:0 ? a:1 : '/')
  endif
  let results = s:uniq(sort(type(a:results) == type("") ? split(a:results,"\n") : copy(a:results)))
  call filter(results,'v:val !~# "\\~$"')
  if a:A =~# '\*'
    let regex = s:gsub(a:A,'\*','.*')
    return filter(copy(results),'v:val =~# "^".regex')
  endif
  let filtered = filter(copy(results),'s:startswith(v:val,a:A)')
  if !empty(filtered) | return filtered | endif
  let prefix = s:sub(a:A,'(.*[/]|^)','&_')
  let filtered = filter(copy(results),"s:startswith(v:val,prefix)")
  if !empty(filtered) | return filtered | endif
  let regex = s:gsub(a:A,'[^/]','[&].*')
  let filtered = filter(copy(results),'v:val =~# "^".regex')
  if !empty(filtered) | return filtered | endif
  let regex = s:gsub(a:A,'.','[&].*')
  let filtered = filter(copy(results),'v:val =~# regex')
  return filtered
endfunction

function! s:autocamelize(files,test)
  if a:test =~# '^\u'
    return s:completion_filter(map(copy(a:files),'rails#camelize(v:val)'),a:test)
  else
    return s:completion_filter(a:files,a:test)
  endif
endfunction

function! s:app_relglob(path,glob,...) dict
  if exists("+shellslash") && ! &shellslash
    let old_ss = &shellslash
    let &shellslash = 1
  endif
  let path = a:path
  if path !~ '^/' && path !~ '^\a\+:'
    let path = self.path(path)
  endif
  let suffix = a:0 ? a:1 : ''
  let full_paths = s:glob(path.a:glob.suffix)
  let relative_paths = []
  for entry in full_paths
    if empty(suffix) && s:isdirectory(entry) && entry !~ '/$'
      let entry .= '/'
    endif
    let relative_paths += [entry[strlen(path) : -strlen(suffix)-1]]
  endfor
  if exists("old_ss")
    let &shellslash = old_ss
  endif
  return relative_paths
endfunction

call s:add_methods('app', ['relglob'])

function! s:relglob(...)
  return join(call(rails#app().relglob,a:000,rails#app()),"\n")
endfunction

function! s:controllerList(A,L,P)
  let con = rails#app().relglob("app/controllers/","**/*",".rb")
  call map(con,'s:sub(v:val,"_controller$","")')
  return s:autocamelize(con,a:A)
endfunction

function! s:viewList(A,L,P)
  let c = s:controller(1)
  let top = rails#app().relglob("app/views/",s:fuzzyglob(a:A))
  call filter(top,'v:val !~# "\\~$"')
  if c != '' && a:A !~ '/'
    let local = rails#app().relglob("app/views/".c."/","*.*[^~]")
    return s:completion_filter(local+top,a:A)
  endif
  return s:completion_filter(top,a:A)
endfunction

function! s:layoutList(A,L,P)
  return s:completion_filter(rails#app().relglob("app/views/layouts/","*"),a:A)
endfunction

function! s:fixturesList(A,L,P)
  return s:completion_filter(
        \ rails#app().relglob('test/fixtures/', '**/*') +
        \ rails#app().relglob('spec/fixtures/', '**/*') +
        \ rails#app().relglob('test/factories/', '**/*') +
        \ rails#app().relglob('spec/factories/', '**/*'),
        \ a:A)
endfunction

function! s:localeList(A,L,P)
  return s:completion_filter(rails#app().relglob("config/locales/","**/*"),a:A)
endfunction

function! s:migrationList(A,L,P)
  if a:A =~ '^\d'
    let migrations = rails#app().relglob("db/migrate/",a:A."[0-9_]*",".rb")
    return map(migrations,'matchstr(v:val,"^[0-9]*")')
  else
    let migrations = rails#app().relglob("db/migrate/","[0-9]*[0-9]_*",".rb")
    call map(migrations,'s:sub(v:val,"^[0-9]*_","")')
    return s:autocamelize(migrations,a:A)
  endif
endfunction

function! s:schemaList(A,L,P) abort
  if rails#app().has_path('db/schema.rb')
    let tables = s:readfile(rails#app().path('db/schema.rb'))
    let table_re = '\C^\s\+create_table\s["'':]\zs[^"'',]*\ze'
  else
    let tables = s:readfile(rails#app().path('db/structure.sql'))
    let table_re = s:sql_define . '\zs\i*'
  endif
  call map(tables,'matchstr(v:val, table_re)')
  call filter(tables,'strlen(v:val)')
  call sort(tables)
  return s:completion_filter(tables, a:A)
endfunction

function! s:specList(A,L,P)
  return s:completion_filter(rails#app().relglob("spec/","**/*","_spec.rb"),a:A)
endfunction

function! s:define_navcommand(name, projection) abort
  if empty(a:projection)
    return
  endif
  let name = s:gsub(a:name, '[[:punct:][:space:]]', '')
  if name !~# '^[a-z]\+$'
    return s:error("E182: Invalid command name ".name)
  endif
  for prefix in ['E', 'S', 'V', 'T', 'D']
    exe 'command! -buffer -bar -bang -nargs=* ' .
          \ (prefix =~# 'D' ? '-range=0 ' : '') .
          \ '-complete=customlist,'.s:sid.'CommandList ' .
          \ prefix . name . ' :execute s:CommandEdit(' .
          \ string('<mods> '.(prefix =~# 'D' ? '<line1>' : '') . prefix . "<bang>") . ',' .
          \ string(a:name) . ',' . string(a:projection) . ',<f-args>)'
  endfor
endfunction

function! s:CommandList(A,L,P)
  let cmd = matchstr(a:L,'\C[A-Z]\w\+')
  exe cmd." &"
  let matches = []
  for projection in s:last_projections
    if projection.pattern !~# '\*' || !get(projection, 'complete', 1)
      continue
    endif
    let [prefix, suffix; _] = split(projection.pattern, '\*', 1)
    let results = rails#app().relglob(prefix, '**/*', suffix)
    if suffix =~# '\.rb$' && a:A =~# '^\u'
      let matches += map(results, 'rails#camelize(v:val)')
    else
      let matches += results
    endif
  endfor
  return s:completion_filter(matches, a:A)
endfunction

function! s:CommandEdit(cmd, name, projections, ...)
  if a:0 && a:1 == "&"
    let s:last_projections = a:projections
    return ''
  else
    return rails#buffer().open_command(a:cmd, a:0 ? a:1 : '', a:name, a:projections)
  endif
endfunction

function! s:app_migration(file) dict
  let arg = a:file
  if arg =~ '^0$\|^0\=[#:]'
    let suffix = s:sub(arg,'^0*','')
    if self.has_file('db/seeds.rb') && suffix ==# ''
      return 'db/seeds.rb'
    elseif self.has_file('db/schema.rb')
      return 'db/schema.rb'.suffix
    elseif suffix ==# ''
      return 'db/seeds.rb'
    else
      return 'db/schema.rb'.suffix
    endif
  elseif arg =~ '^\d$'
    let glob = '00'.arg.'_*.rb'
  elseif arg =~ '^\d\d$'
    let glob = '0'.arg.'_*.rb'
  elseif arg =~ '^\d\d\d$'
    let glob = ''.arg.'_*.rb'
  elseif arg == ''
    let glob = '*.rb'
  else
    let glob = '*'.rails#underscore(arg).'*rb'
  endif
  let files = s:glob(self.path('db/migrate/').glob)
  call map(files,'strpart(v:val,1+strlen(self.path()))')
  if arg ==# ''
    return get(files,-1,'')
  endif
  let keep = get(files,0,'')
  if glob =~# '^\*.*\*rb'
    let pattern = glob[1:-4]
    call filter(files,'v:val =~# ''db/migrate/\d\+_''.pattern.''\.rb''')
    let keep = get(files,0,keep)
  endif
  return keep
endfunction

call s:add_methods('app', ['migration'])

function! s:migrationEdit(cmd,...)
  let cmd = s:findcmdfor(a:cmd)
  let arg = a:0 ? a:1 : ''
  if arg =~# '!'
    " This will totally miss the mark if we cross into or out of DST.
    let ts = localtime()
    let local = strftime('%H', ts) * 3600 + strftime('%M', ts) * 60 + strftime('%S')
    let offset = local - ts % 86400
    if offset <= -12 * 60 * 60
      let offset += 86400
    elseif offset >= 12 * 60 * 60
      let offset -= 86400
    endif
    let template = 'class ' . rails#camelize(matchstr(arg, '[^!]*')) . " < ActiveRecord::Migration\nend"
    return rails#buffer().open_command(a:cmd, strftime('%Y%m%d%H%M%S', ts - offset).'_'.arg, 'migration',
          \ [{'pattern': 'db/migrate/*.rb', 'template': template}])
  endif
  let migr = arg == "." ? "db/migrate" : rails#app().migration(arg)
  if migr != ''
    return s:open(cmd, migr)
  else
    return s:error("Migration not found".(arg=='' ? '' : ': '.arg))
  endif
endfunction

function! s:schemaEdit(cmd,...)
  let cmd = s:findcmdfor(a:cmd)
  let schema = 'db/schema.rb'
  if !rails#app().has_file('db/schema.rb')
    if rails#app().has_file('db/structure.sql')
      let schema = 'db/structure.sql'
    elseif rails#app().has_file('db/'.s:environment().'_structure.sql')
      let schema = 'db/'.s:environment().'_structure.sql'
    endif
  endif
  return s:open(cmd,schema.(a:0 && a:1 !=# '.' ? '#'.a:1 : ''))
endfunction

function! s:fixturesEdit(cmd,...)
  if a:0
    let c = rails#underscore(a:1)
  else
    let c = rails#pluralize(s:model(1))
  endif
  if c == ""
    return s:error("E471: Argument required")
  endif
  let e = fnamemodify(c,':e')
  let e = e == '' ? e : '.'.e
  let c = fnamemodify(c,':r')
  let dirs = ['test/fixtures', 'spec/fixtures', 'test/factories', 'spec/factories']
  let file = get(filter(copy(dirs), 's:isdirectory(rails#app().path(v:val))'), 0, dirs[0]).'/'.c.e
  if file =~ '\.\w\+$' && rails#app().find_file(c.e, dirs, []) ==# ''
    return s:edit(a:cmd,file)
  else
    return s:open(a:cmd, rails#app().find_file(c.e, dirs, ['.yml', '.csv', '.rb'], file))
  endif
endfunction

function! s:localeEdit(cmd,...)
  let c = a:0 ? a:1 : rails#app().default_locale()
  if c =~# '\.'
    return s:edit(a:cmd,rails#app().find_file(c,'config/locales',[],'config/locales/'.c))
  else
    return rails#buffer().open_command(a:cmd, c, 'locale',
          \ [{'pattern': 'config/locales/*.yml'}, {'pattern': 'config/locales/*.rb'}])
  endif
endfunction

function! s:dotcmp(i1, i2) abort
  return strlen(s:gsub(a:i1,'[^.]', '')) - strlen(s:gsub(a:i2,'[^.]', ''))
endfunction

let s:view_types = split('rhtml,erb,rxml,builder,rjs,haml',',')

function! s:readable_resolve_view(name, ...) dict abort
  let name = a:name
  if name !~# '/'
    let controller = self.controller_name(1)
    let found = ''
    if controller != ''
      let found = call(self.resolve_view, [controller.'/'.name] + a:000, self)
    endif
    if empty(found)
      let found = call(self.resolve_view, ['application/'.name] + a:000, self)
    endif
    return found
  endif
  if name =~# '/' && !self.app().has_path(fnamemodify('app/views/'.name, ':h'))
    return ''
  elseif name =~# '\.[[:alnum:]_+]\+\.\w\+$' || name =~# '\.\%('.join(s:view_types,'\|').'\)$'
    return self.app().path('app/views/'.name)
  else
    for format in ['.'.self.format(a:0 ? a:1 : 0), '']
      let found = self.app().relglob('', 'app/views/'.name.format.'.*')
      call sort(found, s:function('s:dotcmp'))
      if !empty(found)
        return self.app().path(found[0])
      endif
    endfor
  endif
  return ''
endfunction

function! s:readable_resolve_layout(name, ...) dict abort
  let name = a:name
  if name ==# ''
    let name = self.controller_name(1)
  endif
  let name = 'layouts/'.name
  let view = self.resolve_view(name, a:0 ? a:1 : 0)
  if view ==# '' && a:name ==# ''
    let view = self.resolve_view('layouts/application', a:0 ? a:1 : 0)
  endif
  return view
endfunction

let s:gem_subdirs = {}
function! s:gem_subdirs(...) abort
  let gems = []
  let project = exists('*bundler#project') ? bundler#project() : {}
  if has_key(project, 'sorted')
    let gems = bundler#project().sorted()
  elseif has_key(project, 'paths')
    let gems = values(bundler#project().paths())
  endif
  let gempath = escape(join(gems,','), ' ')
  if empty(gempath)
    return []
  endif
  let key = gempath . "\n" . join(a:000, ',')
  if !has_key(s:gem_subdirs, key)
    if len(s:gem_subdirs) > 512
      let s:gem_subdirs = {}
    endif
    let path = []
    for subdir in a:000
      call extend(path, finddir(subdir, gempath, -1))
    endfor
    call map(path, 'fnamemodify(v:val . "/*", ":p")')
    call sort(path)
    let s:gem_subdirs[key] = path
  endif
  return copy(s:gem_subdirs[key])
endfunction

function! s:asset_path() abort
  let path = []
  let root = ''
  let parent = matchstr(expand('%:p'), '.*\ze[\/]assets[\/]')
  if parent =~# '[\/]\%(app\|lib\|vendor\)$'
    let root = substitute(parent, '[\/]\%(app\|lib\|vendor\)$', '', '')
  elseif !empty(s:glob(parent.'/*.gemspec'))
    let root = parent
    call add(path, parent . '/assets/*')
  endif
  if len(root)
    call extend(path, map(['app/assets/*', 'lib/assets/*', 'vendor/assets/*', 'node_modules'], 'root . "/" . v:val'))
  endif
  return path
endfunction

function! s:resolve_asset(name, ...) abort
  let paths = s:asset_path()
  call extend(paths, s:gem_subdirs('app/assets', 'lib/assets', 'vendor/assets', 'assets'))
  let path = join(map(paths, 'escape(v:val, " ,")'), ',')
  let suffixesadd = &l:suffixesadd
  let exact = s:find_file(a:name, path, a:0 ? (type(a:1) ==# type([]) ? a:1 : s:suffixes(a:1)) : [])
  if !empty(exact)
    return fnamemodify(exact, ':p')
  endif
  return ''
endfunction

function! rails#pack_suffixes(type) abort
  if a:type =~# '^stylesheets\=$\|^css$'
    let suffixes = ['.sass', '.scss', '.css']
  elseif a:type =~# '^javascripts\=$\|^js$'
    let suffixes = ['.coffee', '.js', '.jsx', '.ts', '.vue']
  else
    return []
  endif
  call extend(suffixes, map(copy(suffixes), 'v:val.".erb"'))
  return s:uniq(suffixes)
endfunction

call s:add_methods('readable', ['resolve_view', 'resolve_layout'])

function! s:findview(name) abort
  let view = s:active() ? rails#buffer().resolve_view(a:name, line('.')) : ''
  return empty(view) ? (a:name =~# '\.' ? a:name : a:name . '.' . s:format()) : view
endfunction

function! s:findlayout(name)
  return rails#buffer().resolve_layout(a:name, line('.'))
endfunction

function! s:viewEdit(cmd, ...) abort
  if a:0 && a:1 =~ '^[^!#:]'
    let view = matchstr(a:1,'[^!#:]*')
  elseif rails#buffer().type_name('controller','mailer')
    let view = s:lastmethod(line('.'))
  else
    let view = ''
  endif
  if view == ''
    return s:error("No view name given")
  elseif view == '.'
    return s:edit(a:cmd,'app/views')
  elseif view !~ '/' && s:controller(1) != ''
    let view = s:controller(1) . '/' . view
  endif
  if view !~ '/'
    return s:error("Cannot find view without controller")
  endif
  let found = rails#buffer().resolve_view(view, line('.'))
  let djump = a:0 ? matchstr(a:1,'#.*\|:\d*\ze\%(:in\)\=$') : ''
  if !empty(found)
    return s:edit(a:cmd,found.djump)
  elseif a:0 && a:1 =~# '!'
    let file = 'app/views/'.view
    call s:mkdir_p(rails#app().path(fnamemodify(file, ':h')))
    return s:edit(a:cmd, file)
  else
    return s:open(a:cmd, 'app/views/'.view)
  endif
endfunction

function! s:layoutEdit(cmd,...) abort
  if a:0
    return s:viewEdit(a:cmd,"layouts/".a:1)
  endif
  let file = s:findlayout('')
  if file ==# ""
    let file = "app/views/layouts/application.html.erb"
  endif
  return s:edit(a:cmd, file)
endfunction

function! s:AssetEdit(cmd, name, dir, suffix, fallbacks) abort
  let name = matchstr(a:name, '^[^!#:]*')
  if empty(name)
    let name = s:controller(1)
  endif
  if empty(name)
    return s:error("E471: Argument required")
  endif
  let suffixes = s:suffixes(a:dir)
  let pack_suffixes = rails#app().has('webpack') ? rails#pack_suffixes(suffixes[0][1:-1]) : []
  call extend(pack_suffixes, map(copy(pack_suffixes), '"/index".v:val'))
  for file in map([''] + suffixes, '"app/assets/".a:dir."/".name.v:val') +
        \ map(pack_suffixes, '"app/javascript/packs/".name.v:val') +
        \ map(copy(a:fallbacks), 'printf(v:val, name)') +
        \ [   'public/'.a:dir.'/'.name.suffixes[0],
        \ 'app/assets/'.a:dir.'/'.name.(name =~# '\.' ? '' : a:suffix)]
    if rails#app().has_file(file)
      break
    endif
  endfor
  let jump = matchstr(a:name, '[!#:].*$')
  if name =~# '\.' || a:name =~# '!'
    return s:edit(a:cmd, file . jump)
  else
    return s:open(a:cmd, file . jump)
  endif
endfunction

function! s:javascriptEdit(cmd,...) abort
  return s:AssetEdit(a:cmd, a:0 ? a:1 : '', 'javascripts',
        \ rails#app().has_gem('coffee-rails') ? '.coffee' : '.js', [])
endfunction

function! s:stylesheetEdit(cmd,...) abort
  let fallbacks = []
  if rails#app().has('sass')
    let fallbacks = ['public/stylesheets/sass/%s.sass', 'public/stylesheets/sass/%s.scss']
  endif
  return s:AssetEdit(a:cmd, a:0 ? a:1 : '', 'stylesheets',
        \ rails#app().stylesheet_suffix(), fallbacks)
endfunction

function! s:javascriptList(A, L, P, ...) abort
  let dir = a:0 ? a:1 : 'javascripts'
  let list = rails#app().relglob('app/assets/'.dir.'/','**/*.*','')
  let suffixes = s:suffixes(dir)
  let strip = '\%('.escape(join(suffixes, '\|'), '.*[]~').'\)$'
  call map(list,'substitute(v:val,strip,"","")')
  call extend(list, rails#app().relglob("public/".dir."/","**/*",suffixes[0]))
  for suffix in rails#app().has('webpack') ? rails#pack_suffixes(suffixes[0][1:-1]) : []
    call extend(list, rails#app().relglob("app/javascript/packs/","**/*",suffix))
  endfor
  if !empty(a:0 ? a:2 : [])
    call extend(list, a:2)
    call s:uniq(list)
  endif
  return s:completion_filter(list,a:A)
endfunction

function! s:stylesheetList(A, L, P) abort
  let extra = []
  if rails#app().has('sass')
    let extra = rails#app().relglob('public/stylesheets/sass/','**/*','.s?ss')
  endif
  return s:javascriptList(a:A, a:L, a:P, 'stylesheets', extra)
endfunction

function! s:specEdit(cmd,...) abort
  let describe = s:sub(s:sub(a:0 ? a:1 : '', '^[^/]*/', ''), '!.*', '')
  let type = rails#singularize(matchstr(a:0 ? a:1 : '', '\w\+'))
  if type =~# '^\%(request\|routing\|integration\|feature\)$'
    let describe = '"' . tr(s:transformations.capitalize(describe, {}), '_', ' ') . '"'
  elseif type ==# 'view'
    let describe = '"' . describe . '"'
  else
    let describe = rails#camelize(describe)
  endif
  let describe .= ', type: :' . type
  return rails#buffer().open_command(a:cmd, a:0 ? a:1 : '', 'spec', [
        \ {'pattern': 'spec/*_spec.rb', 'template': "require 'rails_helper'\n\nRSpec.describe ".describe." do\nend"},
        \ {'pattern': 'spec/spec_helper.rb'},
        \ {'pattern': 'spec/rails_helper.rb'}])
endfunction

" }}}1
" Alternate/Related {{{1

function! s:findcmdfor(cmd) abort
  let bang = ''
  if a:cmd =~ '\!$'
    let bang = '!'
    let cmd = s:sub(a:cmd,'\!$','')
  else
    let cmd = a:cmd
  endif
  let cmd = s:mods(cmd)
  let num = matchstr(cmd, '.\{-\}\ze\a*$')
  let cmd = matchstr(cmd, '\a*$')
  if cmd == '' || cmd == 'E' || cmd == 'F'
    return num.'find'.bang
  elseif cmd == 'S'
    return num.'sfind'.bang
  elseif cmd == 'V'
    return 'vert '.num.'sfind'.bang
  elseif cmd == 'T'
    return num.'tab sfind'.bang
  elseif cmd == 'D'
    return num.'read'.bang
  else
    return num.cmd.bang
  endif
endfunction

function! s:editcmdfor(cmd) abort
  let cmd = s:findcmdfor(a:cmd)
  let cmd = s:sub(cmd,'<sfind>','split')
  let cmd = s:sub(cmd,'<find>','edit')
  return cmd
endfunction

function! s:projection_pairs(options)
  let pairs = []
  if has_key(a:options, 'format')
    for format in s:split(a:options.format)
      if format =~# '%s'
        let pairs += [s:split(format, '%s')]
      endif
    endfor
  else
    for prefix in s:split(get(a:options, 'prefix', []))
      for suffix in s:split(get(a:options, 'suffix', []))
        let pairs += [[prefix, suffix]]
      endfor
    endfor
  endif
  return pairs
endfunction

function! s:readable_open_command(cmd, argument, name, projections) dict abort
  let cmd = s:editcmdfor(s:sub(a:cmd, '^R', ''))
  let djump = ''
  if a:argument =~ '[#!]\|:\d*\%(:in\)\=$'
    let djump = matchstr(a:argument,'!.*\|#\zs.*\|:\zs\d*\ze\%(:in\)\=$')
    let argument = s:sub(a:argument,'[#!].*|:\d*%(:in)=$','')
  else
    let argument = a:argument
  endif

  for projection in a:projections
    if argument ==# '.' && projection.pattern =~# '\*'
      let file = split(projection.pattern, '\*')[0]
    elseif projection.pattern =~# '\*'
      if !empty(argument)
        let root = argument
      elseif get(projection, 'affinity', '') =~# '\%(model\|resource\)$'
        let root = self.model_name(1)
      elseif get(projection, 'affinity', '') =~# '^\%(controller\|collection\)$'
        let root = self.controller_name(1)
      else
        continue
      endif
      let file = s:sub(projection.pattern, '\*', root)
    elseif empty(argument) && projection.pattern !~# '\*'
      let file = projection.pattern
    else
      let file = ''
    endif
    if !empty(file) && self.app().has_path(file)
      let file = fnamemodify(self.app().path(file), ':.')
      return cmd . ' ' . s:jumpargs(file, djump)
    endif
  endfor
  if empty(argument)
    let defaults = filter(map(copy(a:projections), 'v:val.pattern'), 'v:val !~# "\\*"')
    if empty(defaults)
      return 'echoerr "E471: Argument required"'
    else
      return cmd . ' ' . s:fnameescape(defaults[0])
    endif
  endif
  if djump !~# '^!'
    return 'echoerr '.string('No such '.tr(a:name, '_', ' ').' '.root)
  endif
  for projection in a:projections
    if projection.pattern !~# '\*'
      continue
    endif
    let [prefix, suffix; _] = split(projection.pattern, '\*', 1)
    if self.app().has_path(prefix)
      let relative = prefix . (suffix =~# '\.rb$' ? rails#underscore(root) : root) . suffix
      let file = self.app().path(relative)
      call s:mkdir_p(fnamemodify(file, ':h'))
      if has_key(projection, 'template')
        let template = s:split(projection.template)
        if type(get(template, 0)) == type([])
          let template = template[0]
        endif
        let ph = {
              \ 'match': root,
              \ 'file': file,
              \ 'project': self.app().path()}
        call map(template, 's:expand_placeholders(v:val, ph)')
        call map(template, 's:gsub(v:val, "\t", "  ")')
        let file = fnamemodify(s:simplify(file), ':.')
        return cmd . ' ' . s:fnameescape(file) . '|call setline(1, '.string(template).')' . '|set nomod'
      else
        return cmd . ' +AD ' . s:fnameescape(file)
      endif
    endif
  endfor
  return 'echoerr '.string("Couldn't find destination directory for ".a:name.' '.a:argument)
endfunction

call s:add_methods('readable', ['open_command'])

function! s:find(cmd, file) abort
  let djump = matchstr(a:file,'!.*\|#\zs.*\|:\zs\d*\ze\%(:in\)\=$')
  let file = s:sub(a:file,'[#!].*|:\d*%(:in)=$','')
  if file =~# '^\.\.\=\%([\/]\|$\)'
    let file = s:simplify(rails#app().path() . s:sub(file[1:-1], '^\.', '/..'))
  endif
  let cmd = (empty(a:cmd) ? '' : s:findcmdfor(a:cmd))
  if djump =~# '!'
    call s:mkdir_p(rails#app().path(fnamemodify(file, ':h')))
    return s:editcmdfor(cmd) . ' ' . s:jumpargs(fnamemodify(file, ':~:.'), djump)
  else
    return cmd . ' ' . s:jumpargs(file, djump)
  endif
endfunction

function! s:open(cmd, file) abort
  return s:find(a:cmd, rails#app().path(a:file))
endfunction

function! s:edit(cmd, file) abort
  return s:open(s:editcmdfor(a:cmd), a:file)
endfunction

function! s:AR(cmd,related,line1,line2,count,...) abort
  if a:0
    let cmd = ''
    let i = 1
    while i < a:0
      let cmd .= ' ' . s:escarg(a:{i})
      let i += 1
    endwhile
    let file = a:{i}
    if file =~# '^#\h'
      return s:jump(file[1:-1], s:sub(a:cmd, 'D', 'E'))
    elseif a:count && a:cmd !~# 'D'
      let c = a:count
      let tail = matchstr(file,'[#!].*$\|:\d*\%(:in\>.*\)\=$')
      if tail != ""
        let file = s:sub(file,'[#!].*$|:\d*%(:in>.*)=$','')
      endif
      if file != ""
        if a:related
          if file =~# '\u'
            let file = rails#underscore(file)
          endif
          let found = rails#app().find_file(file, rails#app().internal_load_path(), ['.rb'], a:count)
          if !empty(found)
            let file = fnamemodify(found, ':p')
            let c = ''
          else
            let c = 99999999
          endif
        endif
      endif
      return c.s:find(a:cmd . cmd, file . tail)
    else
      let cmd = s:editcmdfor((a:count ? a:count : '').a:cmd) . cmd
      return s:edit(cmd, file)
    endif
  elseif a:cmd =~# 'D'
    let modified = &l:modified
    let template = s:split(get(rails#buffer().projected('template'), 0, []))
    call map(template, 's:gsub(v:val, "\t", "  ")')
    if a:line2 == a:count
      call append(a:line2, template)
    else
      silent %delete_
      call setline(1, template)
      if !modified && !s:filereadable(expand('%'))
        setlocal nomodified
      endif
    endif
    return ''
  else
    let line = a:related ? a:line1 : a:count
    let file = get(b:, line ? 'rails_related' : 'rails_alternate')
    if empty(file)
      let file = rails#buffer().alternate(line)
    endif
    let has_path = !empty(file) && rails#app().has_path(file)
    if empty(file) && exists('b:projectionist') && exists('*projectionist#query_file')
      try
        let expn = line ? {'lnum': line} : {}
        let method = rails#buffer().last_method(line)
        if len(method)
          let expn.define = method
        endif
        for alt in projectionist#query_file('alternate', expn)
          if s:getftime(alt) !=# -1
            return s:find(a:cmd, alt)
          endif
        endfor
      catch
      endtry
    endif
    let confirm = &confirm || (histget(':', -1) =~# '\%(^\||\)\s*conf\%[irm]\>')
    if confirm && !line && !has_path
      let projected = rails#buffer().projected_with_raw('alternate')
      call filter(projected, 'rails#app().has_path(matchstr(v:val[1], "^[^{}]*/"))')
      if len(projected)
        let choices = ['Create alternate file?']
        let i = 0
        for [alt, _] in projected
          let i += 1
          call add(choices, i.' '.alt)
        endfor
        let i = inputlist(choices)
        if i > 0 && i <= len(projected)
          let file = projected[i-1][0] . '!'
        else
          return ''
        endif
      endif
    endif
    if empty(file)
      call s:error("No alternate file defined")
      return ''
    else
      return s:find(a:cmd, rails#app().path(file))
    endif
  endif
endfunction

function! s:Alternate(cmd,line1,line2,count,...) abort
  return call('s:AR',[a:cmd,0,a:line1,a:line2,a:count]+a:000)
endfunction

function! s:Related(cmd,line1,line2,count,...) abort
  return call('s:AR',[a:cmd,1,a:line1,a:line2,a:count]+a:000)
endfunction

function! s:Complete_alternate(A,L,P) abort
  if a:L =~# '^[[:alpha:]]' || a:A =~# '^\w*:\|^\.\=[\/]'
    return s:Complete_edit(a:A,a:L,a:P)
  else
    let seen = {}
    for glob in filter(s:pathsplit(&l:path), 's:startswith(v:val,rails#app().path())')
      for path in s:glob(glob)
        for file in s:glob(path.'/'.s:fuzzyglob(a:A))
          let file = file[strlen(path) + 1 : ]
          let file = substitute(file, '\%('.escape(tr(&l:suffixesadd, ',', '|'), '.|').'\)$', '', '')
          let seen[file] = 1
        endfor
      endfor
    endfor
    return s:completion_filter(sort(keys(seen)), a:A)
  endif
endfunction

function! s:Complete_related(A,L,P) abort
  if a:L =~# '^[[:alpha:]]' || a:A =~# '^\w*:\|^\.\=[\/]'
    return s:Complete_edit(a:A,a:L,a:P)
  else
    let seen = {}
    for path in rails#app().internal_load_path()
      let path = path[strlen(rails#app().path()) + 1 : ]
      if path !~# '[][*]\|^\.\=$\|^vendor\>'
        for file in rails#app().relglob(empty(path) ? '' : path.'/',s:fuzzyglob(rails#underscore(a:A)), a:A =~# '\u' ? '.rb' : '')
          let file = substitute(file, '\.rb$', '', '')
          let seen[file] = 1
        endfor
      endif
    endfor
    return s:autocamelize(sort(keys(seen)), a:A)
  endif
endfunction

function! s:readable_alternate_candidates(...) dict abort
  let f = self.name()
  let placeholders = self.placeholders(a:0 ? a:1 : 0)
  if a:0 && a:1
    let lastmethod = get(placeholders, 'define', '')
    let projected = self.projected('related', placeholders)
    if !empty(projected)
      return projected
    endif
    if self.type_name('controller', 'mailer', 'mailerpreview') && len(lastmethod)
      let view = self.resolve_view(lastmethod, line('.'))
      if view !=# ''
        return [view]
      else
        return [s:sub(s:sub(s:sub(f,'/application%(_controller)=\.rb$','/shared_controller.rb'),'/%(controllers|models|mailers)/','/views/'),'%(_controller)=\.rb$','/'.lastmethod)]
      endif
    elseif f =~# '^config/environments/'
      return ['config/database.yml#'. fnamemodify(f,':t:r')]
    elseif f ==# 'config/database.yml'
      if len(lastmethod)
        return ['config/environments/'.lastmethod.'.rb']
      else
        return ['config/application.rb', 'config/environment.rb']
      endif
    elseif self.type_name('view-layout')
      return [s:sub(s:sub(f,'/views/','/controllers/'),'/layouts/(\k+)\..*$','/\1_controller.rb')]
    elseif self.type_name('view')
       return [s:sub(s:sub(f,'/views/','/controllers/'),'/(\k+%(\.\k+)=)\..*$','_controller.rb#\1'),
             \ s:sub(s:sub(f,'/views/','/mailers/'),'/(\k+%(\.\k+)=)\..*$','.rb#\1'),
             \ s:sub(s:sub(f,'/views/','/models/'),'/(\k+)\..*$','.rb#\1')]
    elseif self.type_name('controller')
      return [s:sub(s:sub(f,'/controllers/','/helpers/'),'%(_controller)=\.rb$','_helper.rb')]
    elseif self.type_name('mailer')
      return [s:sub(s:sub(f,'^app/mailers/','test/mailers/previews/'),'\.rb$','_preview.rb'),
            \ s:sub(s:sub(f,'^app/mailers/','spec/mailers/previews/'),'\.rb$','_preview.rb')]
    elseif self.type_name('model-record')
      let table_name = matchstr(join(self.getline(1,50),"\n"),'\n\s*self\.table_name\s*=\s*[:"'']\zs\w\+')
      if empty(table_name)
        let table_name = rails#pluralize(s:gsub(s:sub(fnamemodify(f,':r'),'.{-}<app/models/',''),'/','_'))
      endif
      return ['db/schema.rb#'.table_name,
            \ 'db/structure.sql#'.table_name,
            \ 'db/'.s:environment().'_structure.sql#'.table_name]
    elseif self.type_name('model-observer')
      return [s:sub(f,'_observer\.rb$','.rb')]
    elseif self.type_name('db-schema') && !empty(lastmethod)
      return ['app/models/' . rails#singularize(lastmethod) . '.rb']
    endif
  endif
  let projected = self.projected('alternate', placeholders)
  if !empty(projected) && f !~# '\<spec/views/.*_spec\.rb$'
    return projected
  endif
  if f =~# '^db/migrate/'
    let migrations = sort(self.app().relglob('db/migrate/','*','.rb'))
    let me = matchstr(f,'\<db/migrate/\zs.*\ze\.rb$')
    if !exists('lastmethod') || lastmethod ==# 'down' || (a:0 && a:1 == 1)
      let candidates = reverse(filter(copy(migrations),'v:val < me'))
      let migration = "db/migrate/".get(candidates,0,migrations[-1]).".rb"
    else
      let candidates = filter(copy(migrations),'v:val > me')
      let migration = "db/migrate/".get(candidates,0,migrations[0]).".rb"
    endif
    return [migration . (exists('lastmethod') && !empty(lastmethod) ? '#'.lastmethod : '')]
  elseif f =~# '\<application\.js$'
    return ['app/helpers/application_helper.rb']
  elseif f =~# 'spec\.js$'
    return [s:sub(s:sub(f, 'spec/javascripts', 'app/assets/javascripts'), '_spec.js', '.js')]
  elseif f =~# 'Spec\.js$'
    return [s:sub(s:sub(f, 'spec/javascripts', 'app/assets/javascripts'), 'Spec.js', '.js')]
  elseif f =~# 'spec\.coffee$'
    return [s:sub(s:sub(f, 'spec/javascripts', 'app/assets/javascripts'), '_spec.coffee', '.coffee')]
  elseif f =~# 'spec\.js\.coffee$'
    return [s:sub(s:sub(f, 'spec/javascripts', 'app/assets/javascripts'), '_spec.js.coffee', '.js.coffee')]
  elseif self.type_name('javascript')
    if f =~# 'public/javascripts'
      let to_replace = 'public/javascripts'
    else
      let to_replace = 'app/assets/javascripts'
    endif
    if f =~# '\.coffee$'
      let suffix = '.coffee'
      let suffix_replacement = '_spec.coffee'
    elseif f =~# '[A-Z][a-z]\+\.js$'
      let suffix = '.js'
      let suffix_replacement = 'Spec.js'
    else
      let suffix = '.js'
      let suffix_replacement = '_spec.js'
    endif
    return [s:sub(s:sub(f, to_replace, 'spec/javascripts'), suffix, suffix_replacement)]
  elseif self.type_name('db-schema') || f =~# '^db/\w*structure.sql$'
    return ['db/seeds.rb']
  elseif f ==# 'db/seeds.rb'
    return ['db/schema.rb', 'db/structure.sql', 'db/'.s:environment().'_structure.sql']
  elseif self.type_name('spec-view')
    return [s:sub(s:sub(f,'<spec/','app/'),'_spec\.rb$','')]
  else
    return self.test_file_candidates()
  endif
endfunction

function! s:readable_alternate(...) dict abort
  let candidates = self.alternate_candidates(a:0 ? a:1 : 0)
  for file in candidates
    if self.app().has_path(s:sub(file, '#.*', ''))
      return file
    endif
  endfor
  return get(candidates, 0, '')
endfunction

" For backwards compatibility
function! s:readable_related(...) dict abort
  return self.alternate(a:0 ? a:1 : 0)
endfunction

call s:add_methods('readable', ['alternate_candidates', 'alternate', 'related'])

" }}}1
" Extraction {{{1

function! s:ViewExtract(bang, mods, first, last, file) abort
  if a:file =~# '[^a-z0-9_/.]'
    return s:error("Invalid partial name")
  endif
  let rails_root = rails#app().path()
  let ext = expand("%:e")
  let file = s:sub(a:file, '%(/|^)\zs_\ze[^/]*$','')
  if rails#buffer().type_name('view-layout')
    if rails#buffer().name() =~# '^app/views/layouts/application\>'
      let curdir = 'app/views/shared'
      if file !~ '/'
        let file = "shared/" .file
      endif
    else
      let curdir = s:sub(rails#buffer().name(),'.*<app/views/layouts/(.*)%(\.\w*)$','app/views/\1')
    endif
  else
    let curdir = fnamemodify(rails#buffer().name(),':h')
  endif
  let curdir = rails_root.'/'.curdir
  let dir = fnamemodify(file,':h')
  let fname = fnamemodify(file,':t')
  let name = matchstr(file, '^[^.]*')
  if fnamemodify(fname, ':e') == ''
    let fname .= matchstr(expand('%:t'),'\..*')
  elseif fnamemodify(fname, ':e') !=# ext
    let fname .= '.'.ext
  endif
  if dir =~ '^/'
    let out = (rails_root).dir."/_".fname
  elseif dir == "" || dir == "."
    let out = (curdir)."/_".fname
  elseif s:isdirectory(curdir."/".dir)
    let out = (curdir)."/".dir."/_".fname
  else
    let out = (rails_root)."/app/views/".dir."/_".fname
  endif
  if s:filereadable(out) && !a:bang
    return s:error('E13: File exists (add ! to override)')
  endif
  if a:bang
    call s:mkdir_p(fnamemodify(out, ':h'))
  elseif out !~# '^\a\a\+:' && !isdirectory(fnamemodify(out,':h'))
    return s:error('No such directory')
  endif
  if ext =~? '^\%(rhtml\|erb\|dryml\)$'
    let erub1 = '\<\%\s*'
    let erub2 = '\s*-=\%\>'
  else
    let erub1 = ''
    let erub2 = ''
  endif
  let spaces = matchstr(getline(a:first), '^ *')
  let q = get(g:, 'ruby_quote', '"')
  let renderstr = 'render ' . q . fnamemodify(file, ':r:r') . q
  if ext =~? '^\%(rhtml\|erb\|dryml\)$'
    let renderstr = "<%= ".renderstr." %>"
  elseif ext == "rxml" || ext == "builder"
    let renderstr = "xml << ".s:sub(renderstr,"render ","render(").")"
  elseif ext == "rjs"
    let renderstr = "page << ".s:sub(renderstr,"render ","render(").")"
  elseif ext == "haml" || ext == "slim"
    let renderstr = "= ".renderstr
  elseif ext == "mn"
    let renderstr = "_".renderstr
  endif
  let contents = join(map(getline(a:first, a:last), 's:sub(v:val, "^".spaces, "") . "\n"'), '')
  silent exe a:last.'put =spaces . renderstr'
  silent exe a:first.','.a:last.'delete _'
  let filetype = &filetype
  silent exe s:mods(a:mods) 'split' s:fnameescape(fnamemodify(out, ':.'))
  let existing_last = line('$')
  silent $put =contents
  silent exe '1,' . existing_last . 'delete _'
  if &filetype !=# filetype
    return 'setlocal filetype=' . filetype
  else
    return ''
  endif
endfunction

function! s:RubyExtract(bang, mods, root, before, name) range abort
  let content = getline(a:firstline, a:lastline)
  execute a:firstline.','.a:lastline.'delete_'
  let indent = get(sort(map(filter(copy(content), '!empty(v:val)'), 'len(matchstr(v:val, "^ \\+"))')), 0, 0)
  if indent
    call map(content, 's:sub(v:val, "^".repeat(" ", indent), "  ")')
  endif
  call append(a:firstline-1, repeat(' ', indent).'include '.rails#camelize(a:name))
  let out = rails#app().path(a:root, a:name . '.rb')
  if a:bang
    call s:mkdir_p(out)
  elseif out !~# '^\a\a\+:' && !isdirectory(fnamemodify(out,':h'))
    return s:error('No such directory')
  endif
  execute s:mods(a:mods) 'split' s:fnameescape(out)
  silent %delete_
  call setline(1, ['module '.rails#camelize(a:name)] + a:before + content + ['end'])
endfunction

" }}}1
" Migration Inversion {{{1

function! s:mkeep(str)
  " Things to keep (like comments) from a migration statement
  return matchstr(a:str,' #[^{].*')
endfunction

function! s:mextargs(str,num)
  if a:str =~ '^\s*\w\+\s*('
    return s:sub(matchstr(a:str,'^\s*\w\+\s*\zs(\%([^,)]\+[,)]\)\{,'.a:num.'\}'),',$',')')
  else
    return s:sub(s:sub(matchstr(a:str,'\w\+\>\zs\s*\%([^,){ ]*[, ]*\)\{,'.a:num.'\}'),'[, ]*$',''),'^\s+',' ')
  endif
endfunction

function! s:migspc(line)
  return matchstr(a:line,'^\s*')
endfunction

function! s:invertrange(beg,end)
  let str = ""
  let lnum = a:beg
  while lnum <= a:end
    let line = getline(lnum)
    let add = ""
    if line == ''
      let add = ' '
    elseif line =~ '^\s*\(#[^{].*\)\=$'
      let add = line
    elseif line =~ '\<create_table\>'
      let add = s:migspc(line)."drop_table".s:mextargs(line,1).s:mkeep(line)
      let lnum = s:endof(lnum)
    elseif line =~ '\<drop_table\>'
      let add = s:sub(line,'<drop_table>\s*\(=\s*([^,){ ]*).*','create_table \1 do |t|'."\n".matchstr(line,'^\s*').'end').s:mkeep(line)
    elseif line =~ '\<add_column\>'
      let add = s:migspc(line).'remove_column'.s:mextargs(line,2).s:mkeep(line)
    elseif line =~ '\<remove_column\>'
      let add = s:sub(line,'<remove_column>','add_column')
    elseif line =~ '\<add_index\>'
      let add = s:migspc(line).'remove_index'.s:mextargs(line,1)
      let mat = matchstr(line,':name\s*=>\s*\zs[^ ,)]*')
      if mat != ''
        let add = s:sub(add,'\)=$',', :name => '.mat.'&')
      else
        let mat = matchstr(line,'\<add_index\>[^,]*,\s*\zs\%(\[[^]]*\]\|[:"'."'".']\w*["'."'".']\=\)')
        if mat != ''
          let add = s:sub(add,'\)=$',', :column => '.mat.'&')
        endif
      endif
      let add .= s:mkeep(line)
    elseif line =~ '\<remove_index\>'
      let add = s:sub(s:sub(line,'<remove_index','add_index'),':column\s*\=\>\s*','')
    elseif line =~ '\<rename_\%(table\|column\|index\)\>'
      let add = s:sub(line,'<rename_%(table\s*\(=\s*|%(column|index)\s*\(=\s*[^,]*,\s*)\zs([^,]*)(,\s*)([^,]*)','\3\2\1')
    elseif line =~ '\<change_column\>'
      let add = s:migspc(line).'change_column'.s:mextargs(line,2).s:mkeep(line)
    elseif line =~ '\<change_column_default\>'
      let add = s:migspc(line).'change_column_default'.s:mextargs(line,2).s:mkeep(line)
    elseif line =~ '\<change_column_null\>'
      let add = s:migspc(line).'change_column_null'.s:mextargs(line,2).s:mkeep(line)
    elseif line =~ '\.update_all(\(["'."'".']\).*\1)$' || line =~ '\.update_all \(["'."'".']\).*\1$'
      " .update_all('a = b') => .update_all('b = a')
      let pre = matchstr(line,'^.*\.update_all[( ][}'."'".'"]')
      let post = matchstr(line,'["'."'".'])\=$')
      let mat = strpart(line,strlen(pre),strlen(line)-strlen(pre)-strlen(post))
      let mat = s:gsub(','.mat.',','%(,\s*)@<=([^ ,=]{-})(\s*\=\s*)([^,=]{-})%(\s*,)@=','\3\2\1')
      let add = pre.s:sub(s:sub(mat,'^,',''),',$','').post
    elseif line =~ '^s\*\%(if\|unless\|while\|until\|for\)\>'
      let lnum = s:endof(lnum)
    endif
    if lnum == 0
      return -1
    endif
    if add == ""
      let add = s:sub(line,'^\s*\zs.*','raise ActiveRecord::IrreversibleMigration')
    elseif add == " "
      let add = ""
    endif
    let str = add."\n".str
    let lnum += 1
  endwhile
  let str = s:gsub(str,'(\s*raise ActiveRecord::IrreversibleMigration\n)+','\1')
  return str
endfunction

function! s:Invert(bang)
  let err = "Could not parse method"
  let src = "up"
  let dst = "down"
  let beg = search('\%('.&l:define.'\).*'.src.'\>',"w")
  let end = s:endof(beg)
  if beg + 1 == end
    let src = "down"
    let dst = "up"
    let beg = search('\%('.&l:define.'\).*'.src.'\>',"w")
    let end = s:endof(beg)
  endif
  if !beg || !end
    return s:error(err)
  endif
  let str = s:invertrange(beg+1,end-1)
  if str == -1
    return s:error(err)
  endif
  let beg = search('\%('.&l:define.'\).*'.dst.'\>',"w")
  let end = s:endof(beg)
  if !beg || !end
    return s:error(err)
  endif
  if foldclosed(beg) > 0
    exe beg."foldopen!"
  endif
  if beg + 1 < end
    exe (beg+1).",".(end-1)."delete _"
  endif
  if str != ''
    exe beg.'put =str'
    exe 1+beg
  endif
endfunction

" }}}1
" Cache {{{1

let s:cache_prototype = {'dict': {}}

function! s:cache_clear(...) dict
  if a:0 == 0
    let self.dict = {}
  elseif has_key(self,'dict') && has_key(self.dict,a:1)
    unlet! self.dict[a:1]
  endif
endfunction

function! rails#cache_clear(...)
  if s:active()
    return call(rails#app().cache.clear,a:000,rails#app().cache)
  endif
endfunction

function! s:cache_get(...) dict abort
  if a:0 == 1
    return self.dict[a:1][0]
  else
    return self.dict
  endif
endfunction

function! s:cache_needs(key, ...) dict abort
  return !has_key(self.dict, a:key) || (a:0 && a:1 isnot# get(self.dict[a:key], 1, {}))
endfunction

function! s:cache_set(key, value, ...) dict abort
  let self.dict[a:key] = [a:value] + a:000
endfunction

call s:add_methods('cache', ['clear','needs','get','set'])

let s:app_prototype.cache = s:cache_prototype

" }}}1
" Syntax {{{1

function! s:app_user_classes() dict
  if self.cache.needs("user_classes")
    let controllers = self.relglob("app/controllers/","**/*",".rb")
    call map(controllers,'v:val == "application" ? v:val."_controller" : v:val')
    let classes =
          \ self.relglob("app/models/","**/*",".rb") +
          \ self.relglob("app/jobs/","**/*",".rb") +
          \ controllers +
          \ self.relglob("app/helpers/","**/*",".rb") +
          \ self.relglob("lib/","**/*",".rb")
    call map(classes,'rails#camelize(v:val)')
    call self.cache.set("user_classes",classes)
  endif
  return self.cache.get('user_classes')
endfunction

function! s:app_user_assertions() dict
  if self.cache.needs("user_assertions")
    if self.has_file("test/test_helper.rb")
      let assertions = map(filter(s:readfile(self.path("test/test_helper.rb")),'v:val =~ "^  def assert_"'),'matchstr(v:val,"^  def \\zsassert_\\w\\+")')
    else
      let assertions = []
    endif
    call self.cache.set("user_assertions",assertions)
  endif
  return self.cache.get('user_assertions')
endfunction

call s:add_methods('app', ['user_classes','user_assertions'])

function! rails#sprockets_syntax() abort
  syn match sprocketsPreProc "\%(\w\s*\)\@<!=" contained containedin=.*Comment skipwhite nextgroup=sprocketsInclude
  syn keyword sprocketsInclude require_self
  syn keyword sprocketsInclude require link link_directory link_tree depend_on depend_on_asset stub skipwhite nextgroup=sprocketsIncluded
  syn keyword sprocketsInclude require_directory require_tree skipwhite nextgroup=sprocketsIncludedDir
  syn match sprocketsIncluded /\f\+\|"[^"]*"/ contained
  syn match sprocketsIncludedDir /\f\+\|"[^"]*"/ contained skipwhite nextgroup=sprocketsIncluded
  if &syntax =~# '\<s[ac]ss\>'
    syn region sassFunction contained start="\<\%(asset-data-url\|\%(asset\|image\|font\|video\|audio\|javascript\|stylesheet\)-\(url\|path\)\)\s*(" end=")" contains=cssStringQ,cssStringQQ oneline keepend containedin=cssFontDescriptorBlock
  endif
  hi def link sprocketsPreProc                PreProc
  hi def link sprocketsInclude                Include
  hi def link sprocketsIncludedDir            sprocketsIncluded
  hi def link sprocketsIncluded               String
endfunction

" }}}1
" Database {{{1

let s:yaml = {}
function! rails#yaml_parse_file(file) abort
  if !has_key(s:yaml, a:file)
    let s:yaml[a:file] = [-2]
  endif
  let ftime = getftime(a:file)
  if ftime == s:yaml[a:file][0]
    return s:yaml[a:file][1]
  endif
  let erb = get(g:, 'rails_erb_yaml')
  let json = system('ruby -rjson -ryaml -rerb -e ' .
        \ s:rquote('puts JSON.generate(YAML.load(' .
        \   (erb ? 'ERB.new(ARGF.read).result' : 'ARGF.read').'))')
        \ . ' ' . s:rquote(a:file))
  if !v:shell_error && json =~# '^[[{]'
    let s:yaml[a:file] = [ftime, rails#json_parse(json)]
    return s:yaml[a:file][1]
  endif
  throw 'invalid YAML file: '.a:file
endfunction

function! s:app_db_config(environment) dict
  let all = {}
  let dbfile = self.real('config/database.yml')
  if !self.cache.needs('db_config')
    let all = self.cache.get('db_config')
  elseif filereadable(dbfile)
    try
      let all = rails#yaml_parse_file(dbfile)
      for [e, c] in items(all)
        for [k, v] in type(c) ==# type({}) ? items(c) : []
          if type(v) ==# get(v:, 't_none', 7)
            call remove(c, k)
          endif
        endfor
      endfor
      call self.cache.set('db_config', all)
    catch /^invalid/
    endtry
  endif
  if has_key(all, a:environment)
    return all[a:environment]
  elseif self.has_gem('rails-default-database')
    let db = ''
    if self.has_file('config/application.rb')
      for line in s:readfile(self.path('config/application.rb'), 32)
        let db = matchstr(line,'^\s*config\.database_name\s*=\s*[''"]\zs.\{-\}\ze[''"]')
        if !empty(db)
          break
        endif
      endfor
    endif
    if empty(db)
      let db = s:gsub(fnamemodify(self.path(), ':t'), '[^[:alnum:]]+', '_') .
            \ '_%s'
    endif
    let db = substitute(db, '%s', a:environment, 'g')
    if db !~# '_test$' && a:environment ==# 'test'
      let db .= '_test'
    endif
    if self.has_gem('pg')
      return {'adapter': 'postgresql', 'database': db}
    elseif self.has_gem('mysql') || self.has_gem('mysql2')
      return {'adapter': 'mysql', 'database': db}
    elseif self.has_gem('sqlite3')
      return {'adapter': 'sqlite3', 'database': 'db/'.a:environment.'.sqlite3'}
    endif
  endif
  return {}
endfunction

function! s:url_encode(str, ...) abort
  if type(a:str) ==# get(v:, 't_bool', 6)
    let str = a:str ? 'true' : 'false'
  else
    let str = a:str
  endif
  return substitute(str, '[?@=&<>%#[:space:]' . (a:0 && a:1 == 'path' ? '' : ':/').']', '\=printf("%%%02X", char2nr(submatch(0)))', 'g')
endfunction

function! s:app_db_url(...) dict abort
  let env = a:0 ? a:1 : s:environment()
  if self.has_gem('dotenv') && filereadable(self.real('.env'))
    for line in readfile(self.real('.env'))
      let match = matchstr(line, '^\s*DATABASE_URL=[''"]\=\zs[^''" ]*')
      if !empty(match)
        return match
      endif
    endfor
  endif
  let config = copy(self.db_config(env))
  if has_key(config, 'url')
    return config.url
  endif
  if !has_key(config, 'adapter')
    return ''
  endif
  let adapter = tr(remove(config, 'adapter'), '_', '-')
  let url = adapter . ':'
  if adapter =~# '^sqlite'
    if has_key(config, 'database')
      let path = remove(config, 'database')
    endif
    if !exists('path') || path ==# ':memory:'
      let path = ''
    elseif path !~# '^/\|^\w:[\/]\|^$'
      let path = self.path(path)
    endif
    let url .= s:url_encode(tr(path, '\', '/'), 'path')
  else
    let url .= '//'
    if has_key(config, 'username')
      let url .= s:url_encode(remove(config, 'username'))
    endif
    if has_key(config, 'password')
      let url .= ':' . s:url_encode(remove(config, 'password'))
    endif
    if url !~# '://$'
      let url .= '@'
    endif
    if get(config, 'host') =~# '^[[:xdigit:]:]*:[[:xdigit:]]*$'
      let url .= '[' . remove(config, 'host') . ']'
    elseif has_key(config, 'host')
      let url .= s:url_encode(remove(config, 'host'))
    elseif url =~# '@$' || has_key(config, 'port')
      let url .= 'localhost'
    endif
    if has_key(config, 'port')
      let url .= ':'.remove(config, 'port')
    endif
    if has_key(config, 'database')
      let url .= '/' . s:url_encode(remove(config, 'database'))
    endif
  endif
  if !empty(config)
    let url .= '?' . join(map(items(config), 'v:val[0]."=".s:url_encode(v:val[1])'), '&')
  endif
  return url
endfunction

call s:add_methods('app', ['db_config', 'db_url'])

function! rails#db_canonicalize(url) abort
  let app = rails#app(db#url#file_path(a:url))
  if empty(app)
    throw 'DB: Not a Rails app'
  endif
  let env = db#url#fragment(a:url)
  let url = empty(env) ? app.db_url() : app.db_url(env)
  if empty(url)
    throw 'DB: No Rails database for environment '.env
  endif
  let url = substitute(url, '^[^:]*\ze:', '\=get(g:db_adapters, submatch(0), submatch(0))', '')
  let url = substitute(url, '^[^:]*://\%([^/@]*@\)\=\zs\%(localhost\)\=\([/?].*\)\=[?&]socket=\([^&]*\)', '\2\1', '')
  let url = substitute(url, '[?&].*', '', '')
  let url = substitute(url, '^mysql://\ze[^@]*$', 'mysql://root@', '')
  return url
endfunction

function! rails#db_test_directory(path) abort
  return s:filereadable(a:path . '/config/environment.rb') && s:isdirectory(a:path . '/app')
endfunction

function! rails#db_complete_fragment(url, ...) abort
  let app = rails#app(db#url#file_path(a:url))
  return len(app) ? app.environments() : []
endfunction

" }}}1
" Projections {{{1

function! rails#json_parse(string) abort
  let string = type(a:string) == type([]) ? join(a:string, ' ') : a:string
  if exists('*json_decode')
    return json_decode(string)
  endif
  let [null, false, true] = ['', 0, 1]
  let stripped = substitute(string,'\C"\(\\.\|[^"\\]\)*"','','g')
  if stripped !~# "[^,:{}\\[\\]0-9.\\-+Eaeflnr-u \n\r\t]"
    try
      return eval(substitute(string,"[\r\n]"," ",'g'))
    catch
    endtry
  endif
  throw "invalid JSON: ".string
endfunction

function! s:app_gems() dict abort
  if self.has('bundler') && exists('*bundler#project')
    let project = bundler#project(self.path())
    if has_key(project, 'paths')
      return project.paths()
    elseif has_key(project, 'gems')
      return project.gems()
    endif
  endif
  return {}
endfunction

function! s:app_has_gem(gem) dict abort
  if self.has('bundler') && exists('*bundler#project')
    let project = bundler#project(self.path())
    if has_key(project, 'has')
      return project.has(a:gem)
    elseif has_key(project, 'gems')
      return has_key(bundler#project(self.path()).gems(), a:gem)
    endif
  else
    return 0
  endif
endfunction

function! s:app_smart_projections() dict abort
  let ts = s:getftime(self.path('app/'))
  if self.cache.needs('smart_projections', ts)
    let dict = {}
    for dir in self.relglob('app/', '*s', '/')
      let singular = rails#singularize(dir)
      let glob = 'app/' . dir . '/*_' . singular . '.rb'
      if dir !~# '\v^%(assets|models|views)$' &&
            \ !has_key(s:default_projections, glob) &&
            \ !empty(self.relglob('', glob))
        let dict[glob] = {'type': s:gsub(tolower(singular), '\A+', ' ')}
      endif
    endfor
    if has_key(dict, 'app/mailers/*_mailer.rb') || self.has_rails5()
      let dict['app/mailers/*_mailer.rb'] = {"type": "mailer"}
    else
      let dict['app/mailers/*.rb'] = {"type": "mailer"}
    endif
    call self.cache.set('smart_projections', dict, ts)
  endif
  return self.cache.get('smart_projections')
endfunction

function! s:extend_projection(dest, src) abort
  let dest = copy(a:dest)
  for key in keys(a:src)
    if !has_key(dest, key) && key ==# 'template'
      let dest[key] = [s:split(a:src[key])]
    elseif key ==# 'template'
      let dest[key] = [s:split(a:src[key])] + dest[key]
    elseif !has_key(dest, key) || key ==# 'affinity'
      let dest[key] = a:src[key]
    elseif type(a:src[key]) == type({}) && type(dest[key]) == type({})
      let dest[key] = extend(copy(dest[key]), a:src[key])
    else
      let dest[key] = s:uniq(s:getlist(a:src, key) + s:getlist(dest, key))
    endif
  endfor
  return dest
endfunction

function! s:combine_projections(dest, src, ...) abort
  let extra = a:0 ? a:1 : {}
  if type(a:src) == type({})
    for [pattern, value] in items(a:src)
      for original in type(value) == type([]) ? value : [value]
        let projection = extend(copy(original), extra)
        if !has_key(projection, 'prefix') && !has_key(projection, 'format')
          let a:dest[pattern] = s:extend_projection(get(a:dest, pattern, {}), projection)
        endif
      endfor
    endfor
  endif
  return a:dest
endfunction

let s:default_projections = {
      \  "Gemfile": {"alternate": "Gemfile.lock", "type": "lib"},
      \  "Gemfile.lock": {"alternate": "Gemfile"},
      \  "README": {"alternate": "config/database.yml"},
      \  "README.*": {"alternate": "config/database.yml"},
      \  "Rakefile": {"type": "task"},
      \  "app/channels/*_channel.rb": {
      \    "template": [
      \      "class {camelcase|capitalize|colons}Channel < ActionCable::Channel",
      \      "end"
      \    ],
      \    "type": "channel"
      \  },
      \  "app/controllers/*_controller.rb": {
      \    "affinity": "controller",
      \    "template": [
      \      "class {camelcase|capitalize|colons}Controller < ApplicationController",
      \      "end"
      \    ],
      \    "type": "controller"
      \  },
      \  "app/controllers/concerns/*.rb": {
      \    "affinity": "controller",
      \    "template": [
      \      "module {camelcase|capitalize|colons}",
      \      "\tinclude ActiveSupport::Concern",
      \      "end"
      \    ],
      \    "type": "controller"
      \  },
      \  "app/helpers/*_helper.rb": {
      \    "affinity": "controller",
      \    "template": ["module {camelcase|capitalize|colons}Helper", "end"],
      \    "type": "helper"
      \  },
      \  "app/jobs/*_job.rb": {
      \    "affinity": "model",
      \    "template": [
      \      "class {camelcase|capitalize|colons}Job < ActiveJob::Base",
      \      "end"
      \    ],
      \    "type": "job"
      \  },
      \  "app/mailers/*.rb": {
      \    "affinity": "controller",
      \    "template": [
      \      "class {camelcase|capitalize|colons} < ActionMailer::Base",
      \      "end"
      \    ]
      \  },
      \  "app/models/*.rb": {
      \    "affinity": "model",
      \    "template": ["class {camelcase|capitalize|colons}", "end"],
      \    "type": "model"
      \  },
      \  "app/serializers/*_serializer.rb": {
      \    "template": [
      \      "class {camelcase|capitalize|colons}Serializer < ActiveModel::Serializer",
      \      "end"
      \    ],
      \    "type": "serializer"
      \  },
      \  "config/*.yml": {
      \    "alternate": [
      \      "config/{}.example.yml",
      \      "config/{}.yml.example",
      \      "config/{}.yml.sample"
      \    ]
      \  },
      \  "config/*.example.yml": {"alternate": "config/{}.yml"},
      \  "config/*.yml.example": {"alternate": "config/{}.yml"},
      \  "config/*.yml.sample": {"alternate": "config/{}.yml"},
      \  "config/application.rb": {"alternate": "config/routes.rb"},
      \  "config/environment.rb": {"alternate": "config/routes.rb"},
      \  "config/environments/*.rb": {
      \    "alternate": ["config/application.rb", "config/environment.rb"],
      \    "type": "environment"
      \  },
      \  "config/initializers/*.rb": {"type": "initializer"},
      \  "config/routes.rb": {
      \    "alternate": ["config/application.rb", "config/environment.rb"],
      \    "type": "initializer"
      \  },
      \  "gems.locked": {"alternate": "gems.rb"},
      \  "gems.rb": {"alternate": "gems.locked", "type": "lib"},
      \  "lib/*.rb": {"type": "lib"},
      \  "lib/tasks/*.rake": {"type": "task"}
      \}

let s:has_projections = {
      \  "cucumber": {
      \    "features/*.feature": {
      \      "template": ["Feature: {underscore|capitalize|blank}"],
      \      "type": "integration test"
      \    },
      \    "features/support/env.rb": {"type": "integration test"}
      \  },
      \  "rails2": {"config/environment.rb": {"type": "environment"}},
      \  "rails3": {"config/application.rb": {"type": "environment"}},
      \  "spec": {
      \    "spec/*_spec.rb": {"alternate": "app/{}.rb"},
      \    "spec/controllers/*_spec.rb": {
      \      "template": [
      \        "require 'rails_helper'",
      \        "",
      \        "RSpec.describe {camelcase|capitalize|colons}, type: :controller do",
      \        "end"
      \      ],
      \      "type": "functional test"
      \    },
      \    "spec/features/*_spec.rb": {
      \      "template": [
      \        "require 'rails_helper'",
      \        "",
      \        "RSpec.describe \"{underscore|capitalize|blank}\", type: :feature do",
      \        "end"
      \      ],
      \      "type": "integration test"
      \    },
      \    "spec/helpers/*_spec.rb": {
      \      "template": [
      \        "require 'rails_helper'",
      \        "",
      \        "RSpec.describe {camelcase|capitalize|colons}, type: :helper do",
      \        "end"
      \      ],
      \      "type": "unit test"
      \    },
      \    "spec/integration/*_spec.rb": {
      \      "template": [
      \        "require 'rails_helper'",
      \        "",
      \        "RSpec.describe \"{underscore|capitalize|blank}\", type: :integration do",
      \        "end"
      \      ],
      \      "type": "integration test"
      \    },
      \    "spec/lib/*_spec.rb": {"alternate": "lib/{}.rb"},
      \    "spec/mailers/*_spec.rb": {
      \      "affinity": "controller",
      \      "template": [
      \        "require 'rails_helper'",
      \        "",
      \        "RSpec.describe {camelcase|capitalize|colons}, type: :mailer do",
      \        "end"
      \      ],
      \      "type": "functional test"
      \    },
      \    "spec/mailers/previews/*_preview.rb": {
      \      "affinity": "controller",
      \      "alternate": "app/mailers/{}.rb",
      \      "template": ["class {camelcase|capitalize|colons}Preview < ActionMailer::Preview", "end"]
      \    },
      \    "spec/models/*_spec.rb": {
      \      "affinity": "model",
      \      "template": [
      \        "require 'rails_helper'",
      \        "",
      \        "RSpec.describe {camelcase|capitalize|colons}, type: :model do",
      \        "end"
      \      ],
      \      "type": "unit test"
      \    },
      \    "spec/rails_helper.rb": {"type": "integration test"},
      \    "spec/requests/*_spec.rb": {
      \      "template": [
      \        "require 'rails_helper'",
      \        "",
      \        "RSpec.describe \"{underscore|capitalize|blank}\", type: :request do",
      \        "end"
      \      ],
      \      "type": "integration test"
      \    },
      \    "spec/spec_helper.rb": {"type": "integration test"}
      \  },
      \  "test": {
      \    "test/*_test.rb": {"alternate": "app/{}.rb"},
      \    "test/controllers/*_test.rb": {
      \      "template": [
      \        "require 'test_helper'",
      \        "",
      \        "class {camelcase|capitalize|colons}Test < ActionController::TestCase",
      \        "end"
      \      ],
      \      "type": "functional test"
      \    },
      \    "test/functional/*_test.rb": {
      \      "alternate": ["app/controllers/{}.rb", "app/mailers/{}.rb"],
      \      "template": [
      \        "require 'test_helper'",
      \        "",
      \        "class {camelcase|capitalize|colons}Test < ActionController::TestCase",
      \        "end"
      \      ],
      \      "type": "functional test"
      \    },
      \    "test/helpers/*_test.rb": {
      \      "template": [
      \        "require 'test_helper'",
      \        "",
      \        "class {camelcase|capitalize|colons}Test < ActionView::TestCase",
      \        "end"
      \      ],
      \      "type": "unit test"
      \    },
      \    "test/integration/*_test.rb": {
      \      "template": [
      \        "require 'test_helper'",
      \        "",
      \        "class {camelcase|capitalize|colons}Test < ActionDispatch::IntegrationTest",
      \        "end"
      \      ],
      \      "type": "integration test"
      \    },
      \    "test/lib/*_test.rb": {"alternate": "lib/{}.rb"},
      \    "test/mailers/*_test.rb": {
      \      "affinity": "model",
      \      "template": [
      \        "require 'test_helper'",
      \        "",
      \        "class {camelcase|capitalize|colons}Test < ActionMailer::TestCase",
      \        "end"
      \      ],
      \      "type": "functional test"
      \    },
      \    "test/mailers/previews/*_preview.rb": {
      \      "affinity": "controller",
      \      "alternate": "app/mailers/{}.rb",
      \      "template": ["class {camelcase|capitalize|colons}Preview < ActionMailer::Preview", "end"]
      \    },
      \    "test/models/*_test.rb": {
      \      "affinity": "model",
      \      "template": [
      \        "require 'test_helper'",
      \        "",
      \        "class {camelcase|capitalize|colons}Test < ActiveSupport::TestCase",
      \        "end"
      \      ],
      \      "type": "unit test"
      \    },
      \    "test/jobs/*_test.rb": {
      \      "affinity": "job",
      \      "template": [
      \        "require 'test_helper'",
      \        "",
      \        "class {camelcase|capitalize|colons}Test < ActiveJob::TestCase",
      \        "end"
      \      ],
      \      "type": "unit test"
      \    },
      \    "test/test_helper.rb": {"type": "integration test"},
      \    "test/unit/*_test.rb": {
      \      "affinity": "model",
      \      "alternate": ["app/models/{}.rb", "lib/{}.rb"],
      \      "template": [
      \        "require 'test_helper'",
      \        "",
      \        "class {camelcase|capitalize|colons}Test < ActiveSupport::TestCase",
      \        "end"
      \      ],
      \      "type": "unit test"
      \    },
      \    "test/unit/helpers/*_helper_test.rb": {
      \      "affinity": "controller",
      \      "alternate": "app/helpers/{}_helper.rb"
      \    }
      \  },
      \  "turnip": {
      \    "spec/acceptance/*.feature": {
      \      "template": ["Feature: {underscore|capitalize|blank}"],
      \      "type": "integration test"
      \    }
      \  }
      \}

let s:projections_for_gems = {}
function! s:app_projections() dict abort
  let dict = s:combine_projections({}, s:default_projections)
  for [k, v] in items(s:has_projections)
    if self.has(k)
      call s:combine_projections(dict, v)
    endif
  endfor
  call s:combine_projections(dict, self.smart_projections())
  call s:combine_projections(dict, get(g:, 'rails_projections', ''))
  for gem in keys(get(g:, 'rails_gem_projections', {}))
    if self.has_gem(gem)
      call s:combine_projections(dict, g:rails_gem_projections[gem])
    endif
  endfor
  let gem_path = escape(join(values(self.gems()),','), ' ')
  if !empty(gem_path)
    if !has_key(s:projections_for_gems, gem_path)
      let gem_projections = {}
      for path in ['lib/', 'lib/rails/']
        for file in findfile(path.'projections.json', gem_path, -1)
          try
            call s:combine_projections(gem_projections, rails#json_parse(s:readfile(self.path(file))))
          catch
          endtry
        endfor
      endfor
      let s:projections_for_gems[gem_path] = gem_projections
    endif
    call s:combine_projections(dict, s:projections_for_gems[gem_path])
  endif
  if self.cache.needs('projections')
    call self.cache.set('projections', {})

    let projections = {}
    for file in ['config/projections.json', '.projections.json']
      if self.has_path(file)
        try
          let projections = rails#json_parse(s:readfile(self.path(file)))
          if type(projections) == type({})
            call self.cache.set('projections', projections)
            break
          endif
        catch /^invalid JSON:/
        endtry
      endif
    endfor
  endif

  call s:combine_projections(dict, self.cache.get('projections'))
  return dict
endfunction

call s:add_methods('app', ['gems', 'has_gem', 'smart_projections', 'projections'])

let s:transformations = {}

function! s:transformations.dot(input, o) abort
  return substitute(a:input, '/', '.', 'g')
endfunction

function! s:transformations.underscore(input, o) abort
  return substitute(a:input, '/', '_', 'g')
endfunction

function! s:transformations.colons(input, o) abort
  return substitute(a:input, '/', '::', 'g')
endfunction

function! s:transformations.hyphenate(input, o) abort
  return tr(a:input, '_', '-')
endfunction

function! s:transformations.blank(input, o) abort
  return tr(a:input, '_-', '  ')
endfunction

function! s:transformations.uppercase(input, o) abort
  return toupper(a:input)
endfunction

function! s:transformations.camelcase(input, o) abort
  return substitute(a:input, '[_-]\(.\)', '\u\1', 'g')
endfunction

function! s:transformations.capitalize(input, o) abort
  return substitute(a:input, '\%(^\|/\)\zs\(.\)', '\u\1', 'g')
endfunction

function! s:transformations.dirname(input, o) abort
  return substitute(a:input, '.[^\/]*$', '', '')
endfunction

function! s:transformations.basename(input, o) abort
  return substitute(a:input, '.*[\/]', '', '')
endfunction

function! s:transformations.plural(input, o) abort
  return rails#pluralize(a:input)
endfunction

function! s:transformations.singular(input, o) abort
  return rails#singularize(a:input)
endfunction

function! s:transformations.open(input, o) abort
  return '{'
endfunction

function! s:transformations.close(input, o) abort
  return '}'
endfunction

function! s:transformations.nothing(input, o) abort
  return ''
endfunction

function! s:expand_placeholder(placeholder, expansions) abort
  let transforms = split(a:placeholder[1:-2], '|')
  if has_key(a:expansions, get(transforms, 0, '}'))
    let value = a:expansions[remove(transforms, 0)]
  else
    let value = get(a:expansions, 'match', "\030")
  endif
  for transform in transforms
    if !has_key(s:transformations, transform)
      return "\030"
    endif
    let value = s:transformations[transform](value, a:expansions)
    if value =~# "\030"
      return "\030"
    endif
  endfor
  return value
endfunction

function! s:expand_placeholders(string, placeholders, ...) abort
  if type(a:string) ==# type({}) || type(a:string) == type([])
    return filter(map(copy(a:string), 's:expand_placeholders(v:val, a:placeholders, 1)'), 'type(v:val) !=# type("") || v:val !~# "\030"')
  elseif type(a:string) !=# type('')
    return a:string
  endif
  let ph = extend({'%': '%'}, a:placeholders)
  let value = substitute(a:string, '{[^{}]*}', '\=s:expand_placeholder(submatch(0), ph)', 'g')
  let value = substitute(value, '%\([^: ]\)', '\=get(ph, submatch(1), "\030")', 'g')
  return !a:0 && value =~# "[\001-\006\016-\037]" ? '' : value
endfunction

function! s:readable_projected_with_raw(key, ...) dict abort
  let f = self.name()
  let all = self.app().projections()
  let mine = []
  if has_key(all, f)
    let mine += map(s:getlist(all[f], a:key), '[s:expand_placeholders(v:val, a:0 ? a:1 : {}), v:val]')
  endif
  for pattern in reverse(sort(filter(keys(all), 'v:val =~# "^[^*{}]*\\*[^*{}]*$"'), s:function('rails#lencmp')))
    let [prefix, suffix; _] = split(pattern, '\*', 1)
    if s:startswith(f, prefix) && s:endswith(f, suffix)
      let root = f[strlen(prefix) : -strlen(suffix)-1]
      let ph = extend({
            \ 'match': root,
            \ 'file': self.path(),
            \ 'project': self.app().path(),
            \ '%': '%'}, a:0 ? a:1 : {})
      let mine += map(s:getlist(all[pattern], a:key), '[s:expand_placeholders(v:val, ph), v:val]')
    endif
  endfor
  return filter(mine, '!empty(v:val[0])')
endfunction

function! s:readable_projected(key, ...) dict abort
  return map(self.projected_with_raw(a:key, a:0 ? a:1 : {}), 'v:val[0]')
endfunction

call s:add_methods('readable', ['projected', 'projected_with_raw'])

" }}}1
" Detection {{{1

function! s:app_internal_load_path() dict abort
  let path = ['lib', 'vendor']
  let path += get(g:, 'rails_path_additions', [])
  let path += get(g:, 'rails_path', [])
  let path += ['app/models/concerns', 'app/controllers/concerns', 'app/controllers', 'app/helpers', 'app/mailers', 'app/models', 'app/jobs']

  let true = get(v:, 'true', 1)
  for [key, projection] in items(self.projections())
    if get(projection, 'path', 0) is true || get(projection, 'autoload', 0) is true
          \ || get(projection, 'path', 0) is 1 || get(projection, 'autoload', 0) is 1
          \ && key =~# '\.rb$'
      let path += split(key, '*')[0]
    endif
  endfor
  let projected = get(get(self.projections(), '*.rb', {}), 'path', [])
  let path += filter(type(projected) == type([]) ? projected : [projected], 'type(v:val) == type("")')

  let path += ['app/*']

  if self.has('test')
    let path += ['test', 'test/unit', 'test/functional', 'test/integration', 'test/controllers', 'test/helpers', 'test/mailers', 'test/models', 'test/jobs']
  endif
  if self.has('spec')
    let path += ['spec', 'spec/controllers', 'spec/helpers', 'spec/mailers', 'spec/models', 'spec/views', 'spec/lib', 'spec/features', 'spec/requests', 'spec/integration', 'spec/jobs']
  endif
  if self.has('cucumber')
    let path += ['features']
  endif
  call map(path, 'rails#app().path(v:val)')
  return path
endfunction

call s:add_methods('app', ['internal_load_path'])

nnoremap <SID>: :<C-U><C-R>=v:count ? v:count : ''<CR>
function! s:map_gf() abort
  let pattern = '^$\|_gf(v:count\|[Rr]uby\|[Rr]ails'
  if mapcheck('gf', 'n') =~# pattern
    nmap <buffer><silent> gf         <SID>:find <Plug><cfile><CR>
    let b:undo_ftplugin .= "|sil! exe 'nunmap <buffer> gf'"
  endif
  if mapcheck('<C-W>f', 'n') =~# pattern
    nmap <buffer><silent> <C-W>f     <SID>:sfind <Plug><cfile><CR>
    let b:undo_ftplugin .= "|sil! exe 'nunmap <buffer> <C-W>f'"
  endif
  if mapcheck('<C-W><C-F>', 'n') =~# pattern
    nmap <buffer><silent> <C-W><C-F> <SID>:sfind <Plug><cfile><CR>
    let b:undo_ftplugin .= "|sil! exe 'nunmap <buffer> <C-W><C-F>'"
  endif
  if mapcheck('<C-W>gf', 'n') =~# pattern
    nmap <buffer><silent> <C-W>gf    <SID>:tabfind <Plug><cfile><CR>
    let b:undo_ftplugin .= "|sil! exe 'nunmap <buffer> <C-W>gf'"
  endif
  if mapcheck('<C-R><C-F>', 'c') =~# pattern
    cmap <buffer>         <C-R><C-F> <Plug><cfile>
    let b:undo_ftplugin .= "|sil! exe 'cunmap <buffer> <C-R><C-F>'"
  endif
endfunction

function! rails#update_path(before, after) abort
  if &l:path =~# '\v^\.%(,/%(usr|emx)/include)=,,$'
    let before = []
    let after = []
  else
    let before = &l:path =~# '^\.\%(,\|$\)' ? ['.'] : []
    let after = s:pathsplit(s:sub(&l:path, '^\.%(,|$)', ''))
  endif

  let r = 'substitute(v:val, "^\\a\\a\\+:", "+&", "")'
  let &l:path = s:pathjoin(s:uniq(before + map(a:before, r) + after + map(a:after, r)))
endfunction

function! rails#sprockets_setup(type) abort
  if &l:include =~# 'link\\|require\\|depend_on\\|stub'
    return
  endif

  let path = s:asset_path()
  if empty(path)
    return
  endif
  call rails#update_path(path, s:gem_subdirs('app/assets', 'lib/assets', 'vendor/assets', 'assets'))

  let &l:include .= (empty(&l:include) ? '' : '\|') .
        \ '^\s*[[:punct:]]\+=\s*\%(link\|require\|depend_on\|stub\)\w*'

  let &l:suffixesadd = join(s:suffixes(a:type), ',')

  let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe') . '|setlocal pa= sua= inc='

  let map = ''
  let cfilemap = v:version + has('patch032') >= 704 ? maparg('<Plug><cfile>', 'c', 0, 1) : {}
  if get(cfilemap, 'buffer') && cfilemap.expr && cfilemap.rhs !~# 'rails#\|Ruby'
    let map = string(maparg('<Plug><cfile>', 'c'))
  endif
  let map = 'rails#sprockets_cfile(' . map . ')'
  exe 'cmap <buffer><script><expr> <Plug><cfile>' map
  let b:undo_ftplugin .= "|exe 'sil! cunmap <buffer> <Plug><cfile>'"
  call s:map_gf()
endfunction

function! rails#webpacker_setup(type) abort
  let suf = rails#pack_suffixes(a:type)
  let &l:suffixesadd = join(s:uniq(suf + split(&l:suffixesadd, ',') + ['/package.json'] + map(copy(suf), '"/index".v:val')), ',')
  let parent = matchstr(expand('%:p'), '.*\ze[\/]\w\+[\/]javascript[\/]packs')
  if len(parent) && isdirectory(parent . '/node_modules')
    call rails#update_path([], [parent . '/node_modules'])
  endif
  let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe') . '|setlocal pa= sua='
endfunction

function! rails#ruby_setup() abort
  let exts = ['raw', 'erb', 'html', 'builder', 'ruby', 'coffee', 'haml', 'jbuilder']
  if s:active()
    let path = rails#app().internal_load_path()
    let path += [rails#app().path('app/views')]
    if len(rails#buffer().controller_name())
      let path += [rails#app().path('app/views/'.rails#buffer().controller_name()), rails#app().path('app/views/application')]
    endif
    call add(path, rails#app().path())
    if !rails#app().has_rails5()
      let path += [rails#app().path('vendor/plugins/*/lib'), rails#app().path('vendor/rails/*/lib')]
    endif
    call extend(exts,
          \ filter(map(keys(rails#app().projections()),
          \ 'matchstr(v:val, "^\\Capp/views/\\*\\.\\zs(\\w\\+$")'), 'len(v:val)'))
  else
    let full = matchstr(expand('%:p'), '.*[\/]\%(app\|config\|lib\|test\|spec\)\ze[\/]')
    let name = fnamemodify(full, ':t')
    let dir = fnamemodify(full, ':h')
    if len(dir) && (name ==# 'app' || s:isdirectory(dir . '/app')) && (name ==# 'lib' || s:isdirectory(dir . '/lib'))
      let path = [dir . '/app/*', dir . '/lib']
    else
      return
    endif
  endif
  let format = matchstr(expand('%:p'), '[\/]app[\/]views[\/].*\.\zs\w\+\ze\.\w\+$')
  for ext in exts
    if len(format)
      exe 'setlocal suffixesadd+=.' . format . '.' . ext
    endif
    exe 'setlocal suffixesadd+=.' . ext
  endfor

  let engine_paths = s:gem_subdirs('app')
  call rails#update_path(path, engine_paths)
  cmap <buffer><script><expr> <Plug><cfile> rails#ruby_cfile()
  call s:map_gf()
endfunction

function! rails#buffer_setup() abort
  if !s:active()
    return ''
  endif
  let self = rails#buffer()
  let ft = self.getvar('&filetype')
  let b:rails_cached_file_type = self.calculate_file_type()

  let rp = s:gsub(self.app().path(),'[ ,]','\\&')
  if stridx(&tags,rp.'/tags') == -1
    let &l:tags = rp . '/tags,' . rp . '/tmp/tags,' . &tags
  endif

  call s:BufCommands()
  call s:BufProjectionCommands()

  if ft =~# '^ruby\>'
    call self.setvar('&define',self.define_pattern())
    " This really belongs in after/ftplugin/ruby.vim but we'll be nice
    if exists('g:loaded_surround') && self.getvar('surround_101') == ''
      call self.setvar('surround_5',   "\r\nend")
      call self.setvar('surround_69',  "\1expr: \1\rend")
      call self.setvar('surround_101', "\r\nend")
    endif
    if exists(':UltiSnipsAddFiletypes') == 2
      UltiSnipsAddFiletypes rails
    elseif exists(':SnipMateLoadScope') == 2
      SnipMateLoadScope rails
    endif
  elseif self.name() =~# '\.yml\%(\.example\|sample\)\=$\|\.sql$'
    call self.setvar('&define',self.define_pattern())
  elseif ft =~# '^eruby\>'
    call self.setvar('&define',self.define_pattern())
    if exists("g:loaded_ragtag")
      call self.setvar('ragtag_stylesheet_link_tag', "<%= stylesheet_link_tag '\r' %>")
      call self.setvar('ragtag_javascript_include_tag', "<%= javascript_include_tag '\r' %>")
    endif
  elseif ft =~# '^haml\>'
    call self.setvar('&define',self.define_pattern())
    if exists("g:loaded_ragtag")
      call self.setvar('ragtag_stylesheet_link_tag', "= stylesheet_link_tag '\r'")
      call self.setvar('ragtag_javascript_include_tag', "= javascript_include_tag '\r'")
    endif
  elseif ft =~# 'html\>'
    call self.setvar('&define', '\<id=["'']\=')
  endif
  if ft =~# '^eruby\>'
    if exists("g:loaded_surround")
      if self.getvar('surround_45') == '' || self.getvar('surround_45') == "<% \r %>" " -
        call self.setvar('surround_45', "<% \r %>")
      endif
      if self.getvar('surround_61') == '' " =
        call self.setvar('surround_61', "<%= \r %>")
      endif
      if self.getvar("surround_35") == '' " #
        call self.setvar('surround_35', "<%# \r %>")
      endif
      if self.getvar('surround_101') == '' || self.getvar('surround_101')== "<% \r %>\n<% end %>" "e
        call self.setvar('surround_5',   "<% \r %>\n<% end %>")
        call self.setvar('surround_69',  "<% \1expr: \1 %>\r<% end %>")
        call self.setvar('surround_101', "<% \r %>\n<% end %>")
      endif
    endif
  endif

  compiler rails
  let &l:makeprg = self.app().rake_command('static')
  let &l:errorformat .= ',%\&chdir '.escape(self.app().real(), ',')
  if &l:makeprg =~# 'rails$'
    let &l:errorformat .= ",%\\&buffer=%%:s/.*/\\=rails#buffer(submatch(0)).default_task(exists('l#') ? l# : 0)/"
  elseif &l:makeprg =~# 'rake$'
    let &l:errorformat .= ",%\\&buffer=%%:s/.*/\\=rails#buffer(submatch(0)).default_rake_task(exists('l#') ? l# : 0)/"
    let &l:errorformat = substitute(&l:errorformat, '%\\&completion=rails#complete_\zsrails', 'rake', 'g')
  endif

  let dir = '-dir=' . substitute(s:fnameescape(fnamemodify(self.app().real(), ':~')), '^\\\~', '\~', '') . ' '

  let dispatch = self.projected('dispatch')
  if !empty(dispatch)
    call self.setvar('dispatch', dir . dispatch[0])
  elseif self.name() =~# '^public'
    call self.setvar('dispatch', ':Preview')
  elseif self.name() =~# '^\%(app\|config\|db\|lib\|log\|README\|Rakefile\|test\|spec\|features\)'
    if self.app().has_rails5()
      call self.setvar('dispatch',
            \ dir .
            \ self.app().ruby_script_command('bin/rails') .
            \ " %:s/.*/\\=rails#buffer(submatch(0)).default_task(exists('l#') ? l# : 0)/")
    else
      call self.setvar('dispatch',
            \ dir . '-compiler=rails ' .
            \ self.app().rake_command('static') .
            \ " %:s/.*/\\=rails#buffer(submatch(0)).default_rake_task(exists('l#') ? l# : 0)/")
    endif
  endif

  if !empty(findfile('macros/rails.vim', escape(&runtimepath, ' ')))
    runtime! macros/rails.vim
  endif
  if exists('#User#Rails')
    try
      let [modelines, &modelines] = [&modelines, 0]
      doautocmd User Rails
    finally
      let &modelines = modelines
    endtry
  endif
endfunction

" }}}1
" Autocommands {{{1

augroup railsPluginAuto
  autocmd!
  autocmd BufEnter *
        \ if s:active() |
        \   if get(b:, 'rails_refresh') |
        \     let b:rails_refresh = 0 |
        \     let &filetype = &filetype |
        \     unlet! b:rails_refresh |
        \   endif |
        \   if exists("+completefunc") && &completefunc ==# 'syntaxcomplete#Complete' |
        \     if exists("g:loaded_syntax_completion") |
        \       unlet g:loaded_syntax_completion |
        \       silent! delfunction syntaxcomplete#Complete |
        \     endif |
        \   endif |
        \ endif
  autocmd BufWritePost */config/database.yml      call rails#cache_clear("db_config")
  autocmd BufWritePost */config/projections.json  call rails#cache_clear("projections")
  autocmd BufWritePost */.projections.json        call rails#cache_clear("projections")
  autocmd BufWritePost */test/test_helper.rb      call rails#cache_clear("user_assertions")
  autocmd BufWritePost */config/routes.rb         call rails#cache_clear("routes")
  autocmd BufWritePost */config/application.rb    call rails#cache_clear("default_locale")
  autocmd BufWritePost */config/application.rb    call rails#cache_clear("stylesheet_suffix")
  autocmd BufWritePost */config/environments/*.rb call rails#cache_clear("environments")
  autocmd BufWritePost */tasks/**.rake            call rails#cache_clear("rake_tasks")
  autocmd BufWritePost */generators/**            call rails#cache_clear("generators")
augroup END

" }}}1
" Initialization {{{1

map <SID>xx <SID>xx
let s:sid = s:sub(maparg("<SID>xx"),'xx$','')
unmap <SID>xx
let s:file = expand('<sfile>:p')

if !exists('s:apps')
  let s:apps = {}
endif

" }}}1
" vim:set sw=2 sts=2:
