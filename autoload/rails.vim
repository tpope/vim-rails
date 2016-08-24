" autoload/rails.vim
" Author:       Tim Pope <http://tpo.pe/>

" Install this file as autoload/rails.vim.

if exists('g:autoloaded_rails') || &cp
  finish
endif
let g:autoloaded_rails = '5.2'

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

function! s:function(name)
    return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),''))
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
    if (a:list[i] ==# '' && exists('empty')) || has_key(seen,a:list[i])
      call remove(a:list,i)
    elseif a:list[i] ==# ''
      let i += 1
      let empty = 1
    else
      let seen[a:list[i]] = 1
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
endfunc

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

function! s:sname()
  return fnamemodify(s:file,':t:r')
endfunction

function! s:pop_command()
  if exists("s:command_stack") && len(s:command_stack) > 0
    exe remove(s:command_stack,-1)
  endif
endfunction

function! s:push_chdir(...)
  if !exists("s:command_stack") | let s:command_stack = [] | endif
  if exists("b:rails_root") && (a:0 ? getcwd() !=# rails#app().path() : !s:startswith(getcwd(), rails#app().path()))
    let chdir = exists("*haslocaldir") && haslocaldir() ? "lchdir " : "chdir "
    call add(s:command_stack,chdir.s:escarg(getcwd()))
    exe chdir.s:escarg(rails#app().path())
  else
    call add(s:command_stack,"")
  endif
endfunction

function! s:app_path(...) dict
  if a:0 && a:1 =~# '\%(^\|^\w*:\)[\/]'
    return a:1
  else
    return join([self.root]+a:000,'/')
  endif
endfunction

function! s:app_has_path(path) dict
  return getftime(self.path(a:path)) != -1
endfunction

function! s:app_has_file(file) dict
  return filereadable(self.path(a:file))
endfunction

function! s:app_find_file(name, ...) dict abort
  let trim = strlen(self.path())+1
  if a:0
    let path = s:pathjoin(map(s:pathsplit(a:1),'self.path(v:val)'))
  else
    let path = s:pathjoin([self.path()])
  endif
  let suffixesadd = s:pathjoin(get(a:000,1,&suffixesadd))
  let default = get(a:000,2,'')
  let oldsuffixesadd = &l:suffixesadd
  try
    let &suffixesadd = suffixesadd
    " Versions before 7.1.256 returned directories from findfile
    if type(default) == type(0) && (v:version < 702 || default == -1)
      let all = findfile(a:name,path,-1)
      if v:version < 702
        call filter(all,'!isdirectory(v:val)')
      endif
      call map(all,'s:gsub(strpart(fnamemodify(v:val,":p"),trim),"\\\\","/")')
      return default < 0 ? all : get(all,default-1,'')
    elseif type(default) == type(0)
      let found = findfile(a:name,path,default)
    else
      let i = 1
      let found = findfile(a:name,path)
      while v:version < 702 && found != "" && isdirectory(found)
        let i += 1
        let found = findfile(a:name,path,i)
      endwhile
    endif
    return found == "" ? default : s:gsub(strpart(fnamemodify(found,':p'),trim),'\\','/')
  finally
    let &l:suffixesadd = oldsuffixesadd
  endtry
endfunction

call s:add_methods('app',['path','has_path','has_file','find_file'])

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

function! s:readable_define_pattern() dict abort
  if self.name() =~ '\.yml\%(\.example\)\=$'
    return '^\%(\h\k*:\)\@='
  endif
  let define = '^\s*def\s\+\(self\.\)\='
  if self.name() =~# '\.rake$'
    let define .= "\\\|^\\s*\\%(task\\\|file\\)\\s\\+[:'\"]"
  endif
  if self.name() =~# '/schema\.rb$'
    let define .= "\\\|^\\s*create_table\\s\\+[:'\"]"
  endif
  if self.name() =~# '/\.erb$'
    let define .= '\|\<id=["'']\='
  endif
  if self.name() =~# '/\.haml$'
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
  let format = matchstr(self.getline(a:start), '\%(:formats *=>\|\<formats:\) *\[\= *[:''"]\zs\w\+')
  if format !=# ''
    return format
  endif
  if self.type_name('view')
    let format = fnamemodify(self.path(),':r:e')
    if format == ''
      return get({'rhtml': 'html', 'rxml': 'xml', 'rjs': 'js', 'haml': 'html'},fnamemodify(self.path(),':e'),'')
    else
      return format
    endif
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
  if has_key(self,'getvar') && self.getvar('rails_controller') != ''
    return self.getvar('rails_controller')
  endif
  let [affinity, root] = self.find_affinity()
  if affinity ==# 'controller'
    return root
  elseif affinity ==# 'resource'
    return rails#pluralize(root)
  endif
  if f =~ '\<app/views/layouts/'
    return s:sub(f,'.*<app/views/layouts/(.{-})\..*','\1')
  elseif f =~ '\<app/views/'
    return s:sub(f,'.*<app/views/(.{-})/\w+%(\.[[:alnum:]_+]+)=\.\w+$','\1')
  elseif f =~ '\<app/helpers/.*_helper\.rb$'
    return s:sub(f,'.*<app/helpers/(.{-})_helper\.rb$','\1')
  elseif f =~ '\<app/controllers/.*\.rb$'
    return s:sub(f,'.*<app/controllers/(.{-})%(_controller)=\.rb$','\1')
  elseif f =~ '\<app/mailers/.*\.rb$'
    return s:sub(f,'.*<app/mailers/(.{-})\.rb$','\1')
  elseif f =~ '\<app/apis/.*_api\.rb$'
    return s:sub(f,'.*<app/apis/(.{-})_api\.rb$','\1')
  elseif f =~ '\<app/jobs/.*\.rb$'
    return s:sub(f,'.*<app/jobs/(.{-})%(_job)=\.rb$','\1')
  elseif f =~ '\<test/\%(functional\|controllers\)/.*_test\.rb$'
    return s:sub(f,'.*<test/%(functional|controllers)/(.{-})%(_controller)=_test\.rb$','\1')
  elseif f =~ '\<test/\%(unit/\)\?helpers/.*_helper_test\.rb$'
    return s:sub(f,'.*<test/%(unit/)?helpers/(.{-})_helper_test\.rb$','\1')
  elseif f =~ '\<spec/controllers/.*_spec\.rb$'
    return s:sub(f,'.*<spec/controllers/(.{-})%(_controller)=_spec\.rb$','\1')
  elseif f =~ '\<spec/jobs/.*_spec\.rb$'
    return s:sub(f,'.*<spec/jobs/(.{-})%(_job)=_spec\.rb$','\1')
  elseif f =~ '\<spec/helpers/.*_helper_spec\.rb$'
    return s:sub(f,'.*<spec/helpers/(.{-})_helper_spec\.rb$','\1')
  elseif f =~ '\<spec/views/.*/\w\+_view_spec\.rb$'
    return s:sub(f,'.*<spec/views/(.{-})/\w+_view_spec\.rb$','\1')
  elseif f =~ '\<app/models/.*\.rb$' && self.type_name('mailer')
    return s:sub(f,'.*<app/models/(.{-})\.rb$','\1')
  elseif f =~ '\<\%(public\|app/assets\)/stylesheets/.*\.css\%(\.\w\+\)\=$'
    return s:sub(f,'.*<%(public|app/assets)/stylesheets/(.{-})\.css%(\.\w+)=$','\1')
  elseif f =~ '\<\%(public\|app/assets\)/javascripts/.*\.js\%(\.\w\+\)\=$'
    return s:sub(f,'.*<%(public|app/assets)/javascripts/(.{-})\.js%(\.\w+)=$','\1')
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
  if has_key(self,'getvar') && self.getvar('rails_model') != ''
    return self.getvar('rails_model')
  endif
  let [affinity, root] = self.find_affinity()
  if affinity ==# 'model'
    return root
  elseif affinity ==# 'collection'
    return rails#singularize(root)
  endif
  if f =~ '\<app/models/.*_observer.rb$'
    return s:sub(f,'.*<app/models/(.*)_observer\.rb$','\1')
  elseif f =~ '\<app/models/.*\.rb$'
    return s:sub(f,'.*<app/models/(.*)\.rb$','\1')
  elseif f =~ '\<test/\%(unit\|models\)/.*_observer_test\.rb$'
    return s:sub(f,'.*<test/unit/(.*)_observer_test\.rb$','\1')
  elseif f =~ '\<test/\%(unit\|models\)/.*_test\.rb$'
    return s:sub(f,'.*<test/%(unit|models)/(.*)_test\.rb$','\1')
  elseif f =~ '\<spec/models/.*_spec\.rb$'
    return s:sub(f,'.*<spec/models/(.*)_spec\.rb$','\1')
  elseif f =~ '\<\%(test\|spec\)/blueprints/.*\.rb$'
    return s:sub(f,'.*<%(test|spec)/blueprints/(.{-})%(_blueprint)=\.rb$','\1')
  elseif f =~ '\<\%(test\|spec\)/exemplars/.*_exemplar\.rb$'
    return s:sub(f,'.*<%(test|spec)/exemplars/(.*)_exemplar\.rb$','\1')
  elseif f =~ '\<\%(test/\|spec/\)\=factories/.*_factory\.rb$'
    return s:sub(f,'.*<%(test/|spec/)=factories/(.{-})_factory.rb$','\1')
  elseif f =~ '\<\%(test/\|spec/\)\=fabricators/.*\.rb$'
    return s:sub(f,'.*<%(test/|spec/)=fabricators/(.{-})_fabricator.rb$','\1')
  elseif f =~ '\<\%(test\|spec\)/\%(fixtures\|factories\|fabricators\)/.*\.\w\+$'
    return rails#singularize(s:sub(f,'.*<%(test|spec)/\w+/(.*)\.\w+$','\1'))
  elseif a:0 && a:1
    return rails#singularize(self.controller_name())
  endif
  return ""
endfunction

call s:add_methods('readable', ['find_affinity', 'controller_name', 'model_name'])

function! s:readfile(path,...)
  let nr = bufnr('^'.a:path.'$')
  if nr < 0 && exists('+shellslash') && ! &shellslash
    let nr = bufnr('^'.s:gsub(a:path,'/','\\').'$')
  endif
  if bufloaded(nr)
    return getbufline(nr,1,a:0 ? a:1 : '$')
  elseif !filereadable(a:path)
    return []
  elseif a:0
    return readfile(a:path,'',a:1)
  else
    return readfile(a:path)
  endif
endfunction

function! s:file_lines() dict abort
  let ftime = getftime(self.path())
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

function! s:Complete_environments(...)
  return s:completion_filter(rails#app().environments(),a:0 ? a:1 : "")
endfunction

function! s:warn(str)
  echohl WarningMsg
  echomsg a:str
  echohl None
  " Sometimes required to flush output
  echo ""
  let v:warningmsg = a:str
endfunction

function! s:error(str)
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

function! rails#underscore(str)
  let str = s:gsub(a:str,'::','/')
  let str = s:gsub(str,'(\u+)(\u\l)','\1_\2')
  let str = s:gsub(str,'(\l|\d)(\u)','\1_\2')
  let str = tolower(str)
  return str
endfunction

function! rails#camelize(str)
  let str = s:gsub(a:str,'/(.=)','::\u\1')
  let str = s:gsub(str,'%([_-]|<)(.)','\u\1')
  return str
endfunction

function! rails#singularize(word)
  " Probably not worth it to be as comprehensive as Rails but we can
  " still hit the common cases.
  let word = a:word
  if word =~? '\.js$' || word == ''
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

function! rails#pluralize(word)
  let word = a:word
  if word == ''
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
  let root = s:sub(a:0 ? a:1 : get(b:, 'rails_root', ''), '[\/]$', '')
  if !empty(root)
    if !has_key(s:apps, root) && filereadable(root . '/config/environment.rb')
      let s:apps[root] = deepcopy(s:app_prototype)
      let s:apps[root].root = root
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
  if self.getvar('rails_root') != ''
    return rails#app(self.getvar('rails_root'))
  else
    throw 'Not in a Rails app'
  endif
endfunction

function! s:readable_app() dict abort
  return self._app
endfunction

function! RailsRevision()
  return 1000*matchstr(g:autoloaded_rails,'^\d\+')+matchstr(g:autoloaded_rails,'[1-9]\d*$')
endfunction

function! RailsRoot()
  if exists("b:rails_root")
    return b:rails_root
  else
    return ""
  endif
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
  return s:gsub(fnamemodify(bufname(self.number()),':p'),'\\ @!','/')
endfunction

function! s:buffer_name() dict abort
  let app = self.app()
  let f = s:gsub(resolve(fnamemodify(bufname(self.number()),':p')),'\\ @!','/')
  let f = s:sub(f,'/$','')
  let sep = matchstr(f,'^[^\\/]\{3,\}\zs[\\/]')
  if sep != ""
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

function! RailsFilePath()
  if !exists("b:rails_root")
    return ""
  else
    return rails#buffer().name()
  endif
endfunction

function! RailsFile()
  return RailsFilePath()
endfunction

function! RailsFileType()
  if !exists("b:rails_root")
    return ""
  else
    return rails#buffer().type_name()
  endif
endfunction

function! s:readable_calculate_file_type() dict abort
  let f = self.name()
  let e = fnamemodify(f,':e')
  let r = "-"
  let full_path = self.path()
  let nr = bufnr('^'.full_path.'$')
  if nr < 0 && exists('+shellslash') && ! &shellslash
    let nr = bufnr('^'.s:gsub(full_path,'/','\\').'$')
  endif
  if f == ""
    let r = f
  elseif nr > 0 && getbufvar(nr,'rails_file_type') != ''
    return getbufvar(nr,'rails_file_type')
  elseif f =~ '_controller\.rb$' || f =~ '\<app/controllers/.*\.rb$'
    if join(s:readfile(full_path,50),"\n") =~ '\<wsdl_service_name\>'
      let r = "controller-api"
    else
      let r = "controller"
    endif
  elseif f =~ '\<app/apis/.*_api\.rb'
    let r = "api"
  elseif f =~ '\<test/test_helper\.rb$'
    let r = "test"
  elseif f =~ '\<spec/spec_helper\.rb$'
    let r = "spec"
  elseif f =~ '_helper\.rb$'
    let r = "helper"
  elseif f =~ '\<app/mailers/.*\.rb'
    let r = "mailer"
  elseif f =~ '\<app/jobs/.*\.rb'
    let r = "job"
  elseif f =~ '\<app/models/'
    let top = "\n".join(s:readfile(full_path,50),"\n")
    let class = matchstr(top,"\n".'class\s\+\S\+\s*<\s*\<\zs\S\+\>')
    let type = tolower(matchstr(class, '^Application\zs[A-Z]\w*$\|^Acti\w\w\zs[A-Z]\w*\ze::Base'))
    if type ==# 'mailer' || f =~ '_mailer\.rb$'
      let r = 'mailer'
    elseif class ==# 'ActiveRecord::Observer'
      let r = 'model-observer'
    elseif !empty(type)
      let r = 'model-'.type
    elseif top =~ '\<\%(self\.\%(table_name\|primary_key\)\|has_one\|has_many\|belongs_to\)\>'
      let r = 'model-record'
    else
      let r = 'model'
    endif
  elseif f =~ '\<app/views/.*/_\w\+\%(\.[[:alnum:]_+]\+\)\=\.\w\+$'
    let r = "view-partial-" . e
  elseif f =~ '\<app/views/layouts\>.*\.'
    let r = "view-layout-" . e
  elseif f =~ '\<app/views\>.*\.'
    let r = "view-" . e
  elseif f =~ '\<test/\%(unit\|models\|helpers\|jobs\)/.*_test\.rb$'
    let r = "test-unit"
  elseif f =~ '\<test/\%(functional\|controllers\)/.*_test\.rb$'
    let r = "test-functional"
  elseif f =~ '\<test/integration/.*_test\.rb$'
    let r = "test-integration"
  elseif f =~ '\<test/lib/.*_test\.rb$'
    let r = "test-lib"
  elseif f =~ '\<test/\w*s/.*_test\.rb$'
    let r = s:sub(f,'.*<test/(\w*)s/.*','test-\1')
  elseif f =~ '\<test/.*_test\.rb'
    let r = "test"
  elseif f =~ '\<spec/lib/.*_spec\.rb$'
    let r = 'spec-lib'
  elseif f =~ '\<lib/.*\.rb$'
    let r = 'lib'
  elseif f =~ '\<spec/\w*s/.*_spec\.rb$'
    let r = s:sub(f,'.*<spec/(\w*)s/.*','spec-\1')
  elseif f =~ '\<features/.*\.feature$'
    let r = 'cucumber-feature'
  elseif f =~ '\<features/step_definitions/.*_steps\.rb$'
    let r = 'cucumber-steps'
  elseif f =~ '\<features/.*\.rb$'
    let r = 'cucumber'
  elseif f =~ '\<spec/.*\.feature$'
    let r = 'spec-feature'
  elseif f =~ '\<\%(test\|spec\)/fixtures\>'
    if e == "yml"
      let r = "fixtures-yaml"
    else
      let r = "fixtures" . (e == "" ? "" : "-" . e)
    endif
  elseif f =~ '\<\%(test\|spec\)/\%(factories\|fabricators\)\>'
    let r = "fixtures-replacement"
  elseif f =~ '\<spec/.*_spec\.rb'
    let r = "spec"
  elseif f =~ '\<spec/support/.*\.rb'
    let r = "spec"
  elseif f =~ '\<db/migrate\>'
    let r = "db-migration"
  elseif f=~ '\<db/schema\.rb$'
    let r = "db-schema"
  elseif f =~ '\.rake$' || f =~ '\<\%(Rake\|Cap\)file$' || f =~ '\<config/deploy\.rb$' || f =~ '\<config/deploy/.*\.rb$'
    let r = "task"
  elseif f =~ '\<log/.*\.log$'
    let r = "log"
  elseif e == "css" || e =~ "s[ac]ss" || e == "less"
    let r = "stylesheet-".e
  elseif e == "js"
    let r = "javascript"
  elseif e == "coffee"
    let r = "javascript-coffee"
  elseif e == "html"
    let r = e
  elseif f =~ '\<config/routes\>.*\.rb$'
    let r = "config-routes"
  elseif f =~ '\<config/'
    let r = "config"
  endif
  return r
endfunction

function! s:buffer_type_name(...) dict abort
  let type = getbufvar(self.number(),'rails_cached_file_type')
  if type == ''
    let type = self.calculate_file_type()
  endif
  return call('s:match_type',[type == '-' ? '' : type] + a:000)
endfunction

function! s:readable_type_name(...) dict abort
  let type = self.calculate_file_type()
  return call('s:match_type',[type == '-' ? '' : type] + a:000)
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
          \ 'v:val =~ "^ *config.i18n.default_locale = :[\"'']\\=[A-Za-z-]\\+[\"'']\\= *$"'
          \ ), 'matchstr(v:val,"[A-Za-z-]\\+\\ze[\"'']\\= *$")')
    call self.cache.set('default_locale', get(candidates, 0, 'en'))
  endif
  return self.cache.get('default_locale')
endfunction

function! s:app_stylesheet_suffix() dict abort
  if self.cache.needs('stylesheet_suffix')
    let default = self.has_gem('sass-rails') ? '.css.scss' : '.css'
    let candidates = map(filter(
          \ s:readfile(self.path('config/application.rb')),
          \ 'v:val =~ "^ *config.sass.preferred_syntax *= *:[A-Za-z-]\\+ *$"'
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
        \'turnip': 'spec/acceptance/',
        \'sass': 'public/stylesheets/sass/',
        \'lesscss': 'app/stylesheets/',
        \'coffee': 'app/scripts/'}
  if self.cache.needs('features')
    call self.cache.set('features',{})
  endif
  let features = self.cache.get('features')
  if !has_key(features,a:feature)
    let path = get(map,a:feature,a:feature.'/')
    let features[a:feature] =
          \ !empty(filter(split(path, '|'), 'self.has_path(v:val)'))
  endif
  return features[a:feature]
endfunction

" Returns the subset of ['test', 'spec'] present on the app.
function! s:app_test_suites() dict
  return filter(['test','spec'],'self.has(v:val)')
endfunction

call s:add_methods('app',['default_locale','environments','file','has','stylesheet_suffix','test_suites'])
call s:add_methods('file',['path','name','lines','getline'])
call s:add_methods('buffer',['app','number','path','name','lines','getline','type_name'])
call s:add_methods('readable',['app','relative','absolute','spec','calculate_file_type','type_name','line_count'])

" }}}1
" Ruby Execution {{{1

function! s:app_ruby_command(cmd) dict abort
  return 'ruby '.a:cmd
endfunction

function! s:app_ruby_script_command(cmd) dict abort
  if has('win32')
    return self.ruby_command(a:cmd)
  else
    return a:cmd
  endif
endfunction

function! s:app_static_rails_command(cmd) dict abort
  if self.has_path('bin/rails')
    let cmd = 'bin/rails '.a:cmd
  elseif self.has_path('script/rails')
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
  if self.has_path('.zeus.sock') && a:cmd =~# '^\%(console\|dbconsole\|destroy\|generate\|server\|runner\)\>'
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

function! s:app_eval(ruby,...) dict abort
  let def = a:0 ? a:1 : ""
  if !executable("ruby")
    return def
  endif
  let args = "-r./config/boot -r ".s:rquote(self.path("config/environment"))." -e ".s:rquote(a:ruby)
  let cmd = self.ruby_command(args)
  call s:push_chdir(1)
  try
    silent! let results = system(cmd)
  finally
    call s:pop_command()
  endtry
  return v:shell_error == 0 ? results : def
endfunction

call s:add_methods('app', ['ruby_command','ruby_script_command','static_rails_command','prepare_rails_command','execute_rails_command','start_rails_command','eval'])

" }}}1
" Commands {{{1

function! s:BufCommands()
  call s:BufNavCommands()
  call s:BufScriptWrappers()
  command! -buffer -bar -nargs=+ Rnavcommand :call s:Navcommand(<bang>0,<f-args>)
  command! -buffer -bar -nargs=* -bang Rabbrev :call s:Abbrev(<bang>0,<f-args>)
  command! -buffer -bar -nargs=? -bang -count -complete=customlist,rails#complete_rake Rake    :call s:Rake(<bang>0,!<count> && <line1> ? -1 : <count>,<q-args>)
  command! -buffer -bar -nargs=? -bang -range -complete=customlist,s:Complete_preview Rpreview :call s:Preview(<bang>0,<line1>,<q-args>)
  command! -buffer -bar -nargs=? -bang -range -complete=customlist,s:Complete_preview Rbrowse :call s:Preview(<bang>0,<line1>,<q-args>)
  command! -buffer -bar -nargs=? -bang -range -complete=customlist,s:Complete_preview Preview :call s:Preview(<bang>0,<line1>,<q-args>)
  command! -buffer -bar -nargs=? -bang -complete=customlist,s:Complete_environments   Rlog     :call s:Log(<bang>0,<q-args>)
  command! -buffer -bar -nargs=* -bang                                                Rset     :call s:Set(<bang>0,<f-args>)
  command! -buffer -bar -nargs=0 Rtags       :execute rails#app().tags_command()
  command! -buffer -bar -nargs=0 Ctags       :execute rails#app().tags_command()
  command! -buffer -bar -nargs=0 -bang Rrefresh :if <bang>0|unlet! g:autoloaded_rails|source `=s:file`|endif|call s:Refresh(<bang>0)
  if exists("g:loaded_dbext")
    command! -buffer -bar -nargs=? -complete=customlist,s:Complete_environments Rdbext  :call s:BufDatabase(2,<q-args>)|let b:dbext_buffer_defaulted = 1
  endif
  let ext = expand("%:e")
  if RailsFilePath() =~ '\<app/views/'
    " TODO: complete controller names with trailing slashes here
    command! -buffer -bar -bang -nargs=? -range -complete=customlist,s:controllerList Rextract :<line1>,<line2>call s:Extract(<bang>0,<f-args>)
    command! -buffer -bar -bang -nargs=? -range -complete=customlist,s:controllerList Extract  :<line1>,<line2>call s:Extract(<bang>0,<f-args>)
  elseif rails#buffer().name() =~# '^app/helpers/.*\.rb$'
    command! -buffer -bar -bang -nargs=1 -range Rextract :<line1>,<line2>call s:RubyExtract(<bang>0, 'app/helpers', [], s:sub(<f-args>, '_helper$|Helper$|$', '_helper'))
    command! -buffer -bar -bang -nargs=1 -range Extract  :<line1>,<line2>call s:RubyExtract(<bang>0, 'app/helpers', [], s:sub(<f-args>, '_helper$|Helper$|$', '_helper'))
  elseif rails#buffer().name() =~# '^app/\w\+/.*\.rb$'
    command! -buffer -bar -bang -nargs=1 -range Rextract :<line1>,<line2>call s:RubyExtract(<bang>0, matchstr(rails#buffer().name(), '^app/\w\+/').'concerns', ['  extend ActiveSupport::Concern', ''], <f-args>)
    command! -buffer -bar -bang -nargs=1 -range Extract  :<line1>,<line2>call s:RubyExtract(<bang>0, matchstr(rails#buffer().name(), '^app/\w\+/').'concerns', ['  extend ActiveSupport::Concern', ''], <f-args>)
  endif
  if RailsFilePath() =~ '\<db/migrate/.*\.rb$'
    command! -buffer -bar                 Rinvert  :call s:Invert(<bang>0)
  endif
endfunction

function! s:Log(bang,arg)
  let lf = rails#app().path('log/' . (empty(a:arg) ? s:environment() : a:arg) . '.log')
  if a:bang
    exe 'cgetfile' s:fnameescape(lf)
    clast
  else
    if exists(":Tail") == 2
      exe 'Tail'  s:fnameescape(lf)
    else
      exe 'pedit' s:fnameescape(lf)
    endif
  endif
endfunction

function! rails#new_app_command(bang,...) abort
  if !a:0 || a:1 !=# 'new'
    return 'echoerr '.string('Usage: rails new <path>')
  endif

  let args = copy(a:000)

  if &shellpipe !~# 'tee' && index(args, '--skip') < 0 && index(args, '--force') < 0
    let args += ['--skip']
  endif

  let temp = tempname()
  try
    if &shellpipe =~# '%s'
      let pipe = s:sub(&shellpipe, '\%s', temp)
    else
      let pipe = &shellpipe . ' ' . temp
    endif
    exe '!rails' join(map(copy(args),'s:rquote(v:val)'),' ') pipe
  catch /^Vim:Interrupt/
  endtry

  if isdirectory(expand(args[1]))
    let old_errorformat = &l:errorformat
    let chdir = exists("*haslocaldir") && haslocaldir() ? 'lchdir' : 'chdir'
    let cwd = getcwd()
    try
      exe chdir s:fnameescape(expand(args[1]))
      let &l:errorformat = s:efm_generate
      exe 'cgetfile' temp
      return 'cfirst'
    finally
      let &l:errorformat = old_errorformat
      exe chdir s:fnameescape(cwd)
    endtry
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
    execute cd fnameescape(self.path())
    if self.has_path('.ctags')
      let args = []
    else
      let args = s:split(get(g:, 'rails_ctags_arguments', '--languages=ruby'))
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
  silent doautocmd User BufLeaveRails
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
    if rr != ""
      call setbufvar(i,"rails_refresh",1)
    endif
    let i += 1
  endwhile
  silent doautocmd User BufEnterRails
endfunction

function! s:RefreshBuffer()
  if exists("b:rails_refresh") && b:rails_refresh
    let b:rails_refresh = 0
    let &filetype = &filetype
    unlet! b:rails_refresh
  endif
endfunction

" }}}1
" Rake {{{1

function! s:qf_pre() abort
  let dir = substitute(matchstr(','.&l:errorformat, ',chdir \zs\%(\\.\|[^,]\)*'), '\\,' ,',', 'g')
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
      let output = system(self.rake_command().' -T')
      let lines = split(output, "\n")
    finally
      call s:pop_command()
    endtry
    if v:shell_error != 0
      return []
    endif
    call map(lines,'matchstr(v:val,"^rake\\s\\+\\zs[^][ ]\\+")')
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
    let &l:makeprg = rails#app().rake_command()
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
  let projected = self.projected('test')
  if self.type_name('view')
    let tests = [
          \ fnamemodify(f,':s?\<app/?spec/?')."_spec.rb",
          \ fnamemodify(f,':r:s?\<app/?spec/?')."_spec.rb",
          \ fnamemodify(f,':r:r:s?\<app/?spec/?')."_spec.rb",
          \ s:sub(s:sub(f,'<app/views/','test/controllers/'),'/[^/]*$','_controller_test.rb'),
          \ s:sub(s:sub(f,'<app/views/','test/functional/'),'/[^/]*$','_controller_test.rb')]
  elseif self.type_name('controller-api')
    let tests = [
          \ s:sub(s:sub(f,'/controllers/','/apis/'),'_controller\.rb$','_api.rb')]
  elseif self.type_name('api')
    let tests = [
          \ s:sub(s:sub(f,'/apis/','/controllers/'),'_api\.rb$','_controller.rb')]
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

function! s:readable_default_rake_task(...) dict abort
  let app = self.app()
  let lnum = a:0 ? (a:1 < 0 ? 0 : a:1) : 0

  let taskpat = '\C# rake\s\+\zs.\{-\}\ze\%(\s\s\|#\|$\)'
  if self.getvar('&buftype') == 'quickfix'
    return '-'
  elseif self.getline(lnum) =~# '# rake \S'
    return matchstr(self.getline(lnum),'\C# rake \zs.*')
  elseif self.getline(self.last_method_line(lnum)-1) =~# taskpat
    return matchstr(self.getline(self.last_method_line(lnum)-1), taskpat)
  elseif self.getline(self.last_method_line(lnum)) =~# taskpat
    return matchstr(self.getline(self.last_method_line(lnum)), taskpat)
  elseif self.getline(1) =~# taskpat && !lnum
    return matchstr(self.getline(1), taskpat)
  endif

  let placeholders = {}
  if lnum
    let placeholders.l = lnum
    let placeholders.lnum = lnum
    let placeholders.line = lnum
    let last = self.last_method(lnum)
    if !empty(last)
      let placeholders.d = last
      let placeholders.define = last
    endif
  endif
  let tasks = self.projected('task', placeholders)
  if !empty(tasks)
    return tasks[0]
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
      let method = self.last_method(lnum)
      if method == "down" || lnum == 1
        return "db:migrate:down VERSION=".ver
      elseif method == "up" || lnum == line('$')
        return "db:migrate:up VERSION=".ver
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
  elseif self.type_name('controller') && lnum
    return 'routes CONTROLLER='.self.controller_name()
  else
    let test = self.test_file()
    let with_line = test
    if test ==# self.name()
      let with_line .= (lnum > 0 ? ':'.lnum : '')
    endif
    if empty(test)
      return '--tasks'
    elseif test =~# '^test\>' && self.app().has('rails5')
      return 'test '.s:rquote(with_line)
    elseif test =~# '^test\>'
      let opts = ''
      if test ==# self.name()
        let method = self.app().file(test).last_method(lnum)
        if method =~ '^test_'
          let opts = ' TESTOPTS=-n'.method
        endif
      endif
      if test =~# '^test/\%(unit\|models\|jobs\)\>'
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

function! s:app_rake_command(...) dict abort
  if get(a:, 1, '') !=# 'static' && self.has_path('.zeus.sock') && executable('zeus')
    return 'zeus rake'
  elseif self.has_path('bin/rake')
    return self.ruby_script_command('bin/rake')
  elseif self.has('bundler')
    return 'bundle exec rake'
  else
    return 'rake'
  endif
endfunction

function! rails#complete_rake(A,L,P)
  return s:completion_filter(rails#app().rake_tasks(), a:A, ':')
endfunction

call s:add_methods('readable', ['test_file_candidates', 'test_file', 'default_rake_task'])
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

function! s:scanlineforuris(line)
  let url = matchstr(a:line,"\\v\\C%(%(GET|PUT|POST|DELETE)\\s+|\\w+://[^/]*)/[^ \n\r\t<>\"]*[^] .,;\n\r\t<>\":]")
  if url =~ '\C^\u\+\s\+'
    let method = matchstr(url,'^\u\+')
    let url = matchstr(url,'\s\+\zs.*')
    if method !=? "GET"
      let url .= (url =~ '?' ? '&' : '?') . '_method='.tolower(method)
    endif
  endif
  if url != ""
    return [url]
  else
    return []
  endif
endfunction

function! s:readable_preview_urls(lnum) dict abort
  let urls = []
  let start = self.last_method_line(a:lnum) - 1
  while start > 0 && self.getline(start) =~ '^\s*\%(\%(-\=\|<%\)#.*\)\=$'
    let urls = s:scanlineforuris(self.getline(start)) + urls
    let start -= 1
  endwhile
  let start = 1
  while start < self.line_count() && self.getline(start) =~ '^\s*\%(\%(-\=\|<%\)#.*\)\=$'
    let urls += s:scanlineforuris(self.getline(start))
    let start += 1
  endwhile
  if has_key(self,'getvar') && self.getvar('rails_preview') != ''
    let urls += [self.getvar('rails_preview')]
  endif
  if self.name() =~ '^public/stylesheets/sass/'
    let urls = urls + [s:sub(s:sub(self.name(),'^public/stylesheets/sass/','/stylesheets/'),'\.s[ac]ss$','.css')]
  elseif self.name() =~ '^public/'
    let urls = urls + [s:sub(self.name(),'^public','')]
  elseif self.name() =~ '^app/assets/stylesheets/'
    let urls = urls + ['/assets/application.css']
  elseif self.name() =~ '^app/assets/javascripts/'
    let urls = urls + ['/assets/application.js']
  elseif self.name() =~ '^app/stylesheets/'
    let urls = urls + [s:sub(s:sub(self.name(),'^app/stylesheets/','/stylesheets/'),'\.less$','.css')]
  elseif self.name() =~ '^app/scripts/'
    let urls = urls + [s:sub(s:sub(self.name(),'^app/scripts/','/javascripts/'),'\.coffee$','.js')]
  elseif self.controller_name() != '' && self.controller_name() != 'application'
    if self.type_name('controller') && self.last_method(a:lnum) != ''
      let handler = self.controller_name().'#'.self.last_method(a:lnum)
    elseif self.type_name('controller','view-layout','view-partial')
      let handler = self.controller_name().'#index'
    elseif self.type_name('view')
      let handler = self.controller_name().'#'.fnamemodify(self.name(),':t:r:r')
    endif
    if exists('handler')
      call self.app().route_names()
      for route in values(self.app().cache.get('named_routes'))
        if route.method ==# 'GET' && route.handler ==# handler
          let urls += [s:gsub(s:gsub(route.path, '\([^()]*\)', ''), ':\w+', '1')]

        endif
      endfor
    endif
  endif
  return urls
endfunction

call s:add_methods('readable', ['preview_urls'])

function! s:app_server_pid() dict abort
  for type in ['server', 'unicorn']
    let pidfile = self.path('tmp/pids/'.type.'.pid')
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
    if self.cache.has('server')
      let old = self.cache.get('server')
    else
      let old = {'pid': 0, 'binding': ''}
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

function! s:Complete_preview(A,L,P)
  return rails#buffer().preview_urls(a:L =~ '^\d' ? matchstr(a:L,'^\d\+') : line('.'))
endfunction

" }}}1
" Script Wrappers {{{1

function! s:BufScriptWrappers()
  command! -buffer -bang -bar -nargs=? -complete=customlist,s:Complete_script   Rscript       :execute 'Rails<bang>' empty(<q-args>) ? 'console' : <q-args>
  command! -buffer -bang -bar -nargs=* -complete=customlist,s:Complete_environments Console   :Rails<bang> console <args>
  command! -buffer -bang -bar -nargs=? -count -complete=customlist,s:Complete_script Rails    :execute s:Rails(<bang>0, !<count> && <line1> ? -1 : <count>, <q-args>)
  command! -buffer -bang -bar -nargs=* -complete=customlist,s:Complete_generate Rgenerate     :execute rails#app().generator_command(<bang>0,'generate',<f-args>)
  command! -buffer -bang -bar -nargs=* -complete=customlist,s:Complete_generate Generate      :execute rails#app().generator_command(<bang>0,'generate',<f-args>)
  command! -buffer -bar -nargs=*       -complete=customlist,s:Complete_destroy  Rdestroy      :execute rails#app().generator_command(1,'destroy',<f-args>)
  command! -buffer -bar -nargs=*       -complete=customlist,s:Complete_destroy  Destroy       :execute rails#app().generator_command(1,'destroy',<f-args>)
  command! -buffer -bar -nargs=? -bang -complete=customlist,s:Complete_server   Rserver       :execute rails#app().server_command(<bang>0, 1, <q-args>)
  command! -buffer -bar -nargs=? -bang -complete=customlist,s:Complete_server   Server        :execute rails#app().server_command(0, <bang>0, <q-args>)
  command! -buffer -bang -nargs=? -range=0 -complete=customlist,s:Complete_edit Rrunner       :execute rails#buffer().runner_command(<bang>0, <count>?<line1>:0, <q-args>)
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
  if !empty(a:arg)
    let str = a:arg
  elseif rails#buffer().type_name('spec', 'cucumber')
    return rails#buffer().runner_command(a:bang, a:count, '')
  elseif rails#buffer().type_name('test') && !rails#app().has('rails5')
    return rails#buffer().runner_command(a:bang, a:count, '')
  elseif rails#buffer().name() =~# '^\%(app\|config\|db\|lib\|log\|README\|Rakefile\|test\|spec\|features\)'
    let str = rails#buffer().default_rake_task(a:count)
    if str ==# '--tasks'
      let str = ''
    else
      let rake = 1
    endif
  else
    let str = ''
  endif
  if str =~# '^\%(c\|console\|db\|dbconsole\|s\|server\)\S\@!' && str !~# ' -d\| --daemon\| --help'
    return rails#app().start_rails_command(str, a:bang)
  else
    let [mp, efm, cc] = [&l:mp, &l:efm, get(b:, 'current_compiler', '')]
    try
      compiler rails
      if exists('rake') && !rails#app().has('rails5')
        let &l:makeprg = rails#app().rake_command()
      else
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

    let compiler = get(file.projected('compiler'), 0, compiler)
    if compiler ==# 'testrb' || compiler ==# 'minitest'
      let compiler = 'rubyunit'
    elseif empty(findfile('compiler/'.compiler.'.vim', escape(&rtp, ' ')))
      let compiler = 'ruby'
    endif

    execute 'compiler '.compiler

    if compiler ==# 'ruby'
      let &l:makeprg = self.app().prepare_rails_command('runner')
      let extra = ''
    elseif &makeprg =~# '^\%(testrb\|rspec\|cucumber\)\>' && self.app().has_path('.zeus.sock')
      let &l:makeprg = 'zeus ' . &l:makeprg
    elseif compiler ==# 'rubyunit'
      let &l:makeprg = 'ruby -Itest'
    elseif self.app().has_path('bin/' . &l:makeprg)
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
    let output = system(lsof.' -an -i4tcp -sTCP:LISTEN -p'.a:pid)
    let binding = matchstr(output, '\S\+:\d\+\ze\s\+(LISTEN)\n')
    let binding = s:sub(binding, '^\*', '0.0.0.0')
    if empty(binding)
      let output = system(lsof.' -an -i6tcp -sTCP:LISTEN -p'.a:pid)
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
      \ s:color_efm('%-G', 'invoke', '%f') .
      \ s:color_efm('%-G', 'conflict', '%f') .
      \ s:color_efm('%-G', 'run', '%f') .
      \ s:color_efm('%-G', '%\w%\+', ' ') .
      \ 'Overwrite%.%#%\S%\+  %#%m%\e[0m  %#%f,' .
      \ s:color_efm('', '%m%\>', '%f') .
      \ '%-G%.%#'

function! s:app_generator_command(bang,...) dict
  call self.cache.clear('user_classes')
  call self.cache.clear('features')
  let cmd = join(map(copy(a:000),'s:rquote(v:val)'),' ')
  let old_makeprg = &l:makeprg
  let old_errorformat = &l:errorformat
  try
    let &l:makeprg = self.prepare_rails_command(cmd)
    let &l:errorformat = s:efm_generate . ',chdir '.escape(self.path(), ',')
    noautocmd make!
  finally
    let &l:errorformat = old_errorformat
    let &l:makeprg = old_makeprg
  endtry
  if a:bang || empty(getqflist())
    return ''
  else
    return 'cfirst'
  endif
endfunction

call s:add_methods('app', ['generators','output_command','server_command','generator_command'])

function! s:Complete_script(ArgLead, CmdLine, P) abort
  return rails#complete_rails(a:ArgLead, a:CmdLine, a:P, rails#app())
endfunction

function! rails#complete_rails(ArgLead, CmdLine, P, ...) abort
  if a:0
    let app = a:1
  else
    let manifest = findfile('config/environment.rb', escape(getcwd(), ' ,;').';')
    let app = empty(manifest) ? {} : rails#app(fnamemodify(manifest, ':p:h:h'))
  endif
  let cmd = s:sub(a:CmdLine,'^\u\w*\s+','')
  if cmd =~# '^new\s\+'
    return split(glob(a:ArgLead.'*/'), "\n")
  elseif empty(app)
    return s:completion_filter(['new'], a:ArgLead)
  elseif cmd =~# '^\w*$'
    let cmds = ['generate', 'console', 'server', 'dbconsole', 'destroy', 'plugin', 'runner']
    if app.has('rails5')
      call extend(cmds, app.rake_tasks())
    endif
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
      return s:mailerList(a:ArgLead,"","")
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
  return ""
endfunction

function! s:CustomComplete(A,L,P,cmd)
  let L = "Rscript ".a:cmd." ".s:sub(a:L,'^\h\w*\s+','')
  let P = a:P - strlen(a:L) + strlen(L)
  return s:Complete_script(a:A,L,P)
endfunction

function! s:Complete_server(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"server")
endfunction

function! s:Complete_console(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"console")
endfunction

function! s:Complete_generate(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"generate")
endfunction

function! s:Complete_destroy(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"destroy")
endfunction

function! s:Complete_ruby(A,L,P)
  return s:completion_filter(rails#app().user_classes()+["ActiveRecord::Base"],a:A)
endfunction

" }}}1
" Navigation {{{1

function! s:BufNavCommands()
  command! -buffer -bar -nargs=? -complete=customlist,s:Complete_cd Cd    :cd `=rails#app().path(<q-args>)`
  command! -buffer -bar -nargs=? -complete=customlist,s:Complete_cd Lcd  :lcd `=rails#app().path(<q-args>)`
  command! -buffer -bar -nargs=? -complete=customlist,s:Complete_cd Rcd   :cd `=rails#app().path(<q-args>)`
  command! -buffer -bar -nargs=? -complete=customlist,s:Complete_cd Rlcd :lcd `=rails#app().path(<q-args>)`
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related A     :exe s:Alternate('E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AE    :exe s:Alternate('E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AS    :exe s:Alternate('S<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AV    :exe s:Alternate('V<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AT    :exe s:Alternate('T<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AD    :exe s:Alternate('D<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AR    :exe s:Alternate('D<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related R     :exe   s:Related('E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RE    :exe   s:Related('E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RS    :exe   s:Related('S<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RV    :exe   s:Related('V<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RT    :exe   s:Related('T<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RD    :exe   s:Related('D<bang>',<line1>,<line2>,<count>,<f-args>)
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

function! s:fuzzyglob(arg)
  return s:gsub(s:gsub(a:arg,'[^/.]','[&]*'),'%(/|^)\.@!|\.','&*')
endfunction

function! s:Complete_find(ArgLead, CmdLine, CursorPos)
  let paths = s:pathsplit(&l:path)
  let seen = {}
  for path in paths
    if s:startswith(path,rails#app().path()) && path !~ '[][*]'
      let path = path[strlen(rails#app().path()) + 1 : ]
      for file in rails#app().relglob(path == '' ? '' : path.'/',s:fuzzyglob(rails#underscore(a:ArgLead)), a:ArgLead =~# '\u' ? '.rb' : '')
        let seen[file] = 1
      endfor
    endif
  endfor
  return s:autocamelize(sort(keys(seen)),a:ArgLead)
endfunction

function! s:Complete_edit(ArgLead, CmdLine, CursorPos)
  return s:completion_filter(rails#app().relglob("",s:fuzzyglob(a:ArgLead)),a:ArgLead)
endfunction

function! s:Complete_cd(ArgLead, CmdLine, CursorPos)
  let all = rails#app().relglob("",a:ArgLead."*")
  call filter(all,'v:val =~ "/$"')
  return filter(all,'s:startswith(v:val,a:ArgLead)')
endfunction

function! rails#includeexpr(fname) abort
  if mode() =~# '[iR]' || expand('<cfile>') !=# a:fname
    return s:RailsIncludefind(a:fname)
  else
    return s:RailsIncludefind(a:fname, 1)
  endif
endfunction

function! s:linepeak()
  let line = getline(line("."))
  let line = s:sub(line,'^(.{'.col(".").'}).*','\1')
  let line = s:sub(line,'([:"'."'".']|\%[qQ]=[[({<])=\f*$','')
  return line
endfunction

function! s:matchcursor(pat)
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

function! s:findit(pat,repl)
  let res = s:matchcursor(a:pat)
  if res != ""
    return substitute(res,'\C'.a:pat,a:repl,'')
  else
    return ""
  endif
endfunction

function! s:findamethod(func,repl)
  return s:findit('\s*\<\%('.a:func.'\)\s*(\=\s*[@:'."'".'"]\(\f\+\)\>.\=',a:repl)
endfunction

function! s:findasymbol(sym,repl)
  return s:findit('\s*\%(:\%('.a:sym.'\)\s*=>\|\<'.a:sym.':\)\s*(\=\s*[@:'."'".'"]\(\f\+\)\>.\=',a:repl)
endfunction

function! s:findfromview(func,repl)
  "                     (   )            (           )                      ( \1  )                   (      )
  return s:findit('\s*\%(<%\)\==\=\s*\<\%('.a:func.'\)\s*(\=\s*[@:'."'".'"]\(\f\+\)\>['."'".'"]\=\s*\%(%>\s*\)\=',a:repl)
endfunction

function! s:findasset(path, ext, pre, post) abort
  let asset = rails#app().resolve_asset(a:path, a:ext)
  return len(asset) ? asset : rails#app().path(a:pre . a:path . a:post)
endfunction

function! s:cfile(...) abort
  if filereadable(expand("<cfile>"))
    return expand("<cfile>")
  endif

  " UGH
  let buffer = rails#buffer()
  let format = s:format()

  let ssext = ['css', 'css.*', 'scss', 'sass']
  if buffer.type_name('stylesheet')
    let res = s:findit('^\s*\*=\s*require\s*["'']\=\([^"'' ]*\)', '\1')
    if !empty(res)
      return s:findasset(res, ssext, "app/assets/stylesheets/", ".css")
    endif
    let res = s:findit('^\s*@import\s*\%(url(\)\=["'']\=\([^"'' ]*\)', '\1')
    if res != ""
      let base = expand('%:p:h')
      let rel = s:sub(res, '\ze[^/]*$', '_')
      for ext in ['css', 'css.scss', 'css.sass', 'scss', 'sass']
        for name in [res.'.'.ext, res.'.'.ext.'.erb', rel.'.'.ext, rel.'.'.ext.'.erb']
          if filereadable(base.'/'.name)
            return base.'/'.name
          endif
        endfor
      endfor
      let asset = rails#app().resolve_asset(res, ssext)
      if empty(asset) && expand('%:e') =~# '^s[ac]ss$'
        let asset = rails#app().resolve_asset(rel, ssext)
      endif
      return empty(asset) ? 'app/assets/stylesheets/'.res : asset
    endif
  endif

  let jsext = ['js', 'js.*', 'jst', 'jst.*', 'coffee']
  if buffer.type_name('javascript')
    let res = s:findit('^\s*//=\s*require\s*["'']\=\([^"'' ]*\)', '\1')
    if !empty(res)
      return s:findasset(res, jsext, "app/assets/javascript/", ".js")
    endif
    return expand("<cfile>")
  endif

  let res = s:findit('\v\s*<require\s*\(=\s*File.dirname\(__FILE__\)\s*\+\s*[:'."'".'"](\f+)>.=',expand('%:h').'/\1')
  if res != ""|return res.(fnamemodify(res,':e') == '' ? '.rb' : '')|endif

  let res = s:findit('\v<File.dirname\(__FILE__\)\s*\+\s*[:'."'".'"](\f+)>['."'".'"]=',expand('%:h').'\1')
  if res != ""|return res|endif

  let res = rails#underscore(s:findit('\v\s*<%(include|extend)\(=\s*<([[:alnum:]_:]+)>','\1'))
  if res != ""|return res.".rb"|endif

  let res = s:findamethod('require','\1')
  if res != ""|return res.(fnamemodify(res,':e') == '' ? '.rb' : '')|endif

  let res = s:findamethod('belongs_to\|has_one\|embedded_in\|embeds_one\|composed_of\|validates_associated\|scaffold','\1.rb')
  if res != ""|return res|endif

  let res = rails#singularize(s:findamethod('has_many\|has_and_belongs_to_many\|embeds_many','\1'))
  if res != ""|return res.".rb"|endif

  let res = rails#singularize(s:findamethod('create_table\|change_table\|drop_table\|rename_table\|\%(add\|remove\)_\%(column\|index\|timestamps\|reference\|belongs_to\)\|rename_column\|remove_columns\|rename_index','\1'))
  if res != ""|return res.".rb"|endif

  let res = rails#singularize(s:findasymbol('through','\1'))
  if res != ""|return res.".rb"|endif

  let res = s:findamethod('fixtures','fixtures/\1')
  if res != ""
    return RailsFilePath() =~ '\<spec/' ? 'spec/'.res : res
  endif

  let res = s:findamethod('\%(\w\+\.\)\=resources','\1_controller.rb')
  if res != ""|return res|endif

  let res = s:findamethod('\%(\w\+\.\)\=resource','\1')
  if res != ""|return rails#pluralize(res)."_controller.rb"|endif

  let res = s:findasymbol('to','\1')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  let res = s:findamethod('root\s*\%(:to\s*=>\|\<to:\)\s*','\1')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  let res = s:findamethod('\%(match\|get\|put\|patch\|post\|delete\|redirect\)\s*(\=\s*[:''"][^''"]*[''"]\=\s*\%(\%(,\s*:to\s*\)\==>\|,\s*to:\)\s*','\1')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  if !buffer.type_name('controller', 'mailer')
    let res = s:sub(s:sub(s:findasymbol('layout','\1'),'^/',''),'[^/]+$','_&')
    if res != ""|return s:findview(res)|endif
    let res = s:sub(s:sub(s:findfromview('render\s*(\=\s*\%(:layout\s\+=>\|layout:\)\s*','\1'),'^/',''),'[^/]+$','_&')
    if res != ""|return s:findview(res)|endif
  endif

  let res = s:findamethod('layout','\=s:findlayout(submatch(1))')
  if res != ""|return res|endif

  let res = s:findasymbol('layout','\=s:findlayout(submatch(1))')
  if res != ""|return res|endif

  let res = s:findamethod('helper','\1_helper.rb')
  if res != ""|return res|endif

  let res = s:findasymbol('controller','\1_controller.rb')
  if res != ""|return res|endif

  let res = s:findasymbol('action','\1')
  if res != ""|return s:findview(res)|endif

  let res = s:findasymbol('template','\1')
  if res != ""|return s:findview(res)|endif

  let res = s:sub(s:sub(s:findasymbol('partial','\1'),'^/',''),'[^/]+$','_&')
  if res != ""|return s:findview(res)|endif

  let res = s:sub(s:sub(s:findfromview('json\.(\=\s*\%(:partial\s\+=>\|partial!\)\s*','\1'),'^/',''),'[^/]+$','_&')
  if res != ""|return s:findview(res)|endif

  let res = s:sub(s:sub(s:findfromview('render\s*(\=\s*\%(:partial\s\+=>\|partial:\)\s*','\1'),'^/',''),'[^/]+$','_&')
  if res != ""|return s:findview(res)|endif

  let res = s:findamethod('render\>\s*\%(:\%(template\|action\)\s\+=>\|template:\|action:\)\s*','\1')
  if res != ""|return s:findview(res)|endif

  let res = s:sub(s:findfromview('render','\1'),'^/','')
  if !buffer.type_name('controller', 'mailer')
    let res = s:sub(res,'[^/]+$','_&')
  endif
  if res != ""|return s:findview(res)|endif

  let res = s:findamethod('redirect_to\s*(\=\s*\%\(:action\s\+=>\|\<action:\)\s*','\1')
  if res != ""|return res|endif

  let res = s:findfromview('image[_-]\%(\|path\|url\)\|\%(path\|url\)_to_image','\1')
  if res != ""
    return s:findasset(res, [], 'public/images/', '')
  endif

  let res = s:findfromview('stylesheet[_-]\%(link_tag\|path\|url\)\|\%(path\|url\)_to_stylesheet','\1')
  if res != ""
    return s:findasset(res, ssext, 'public/stylesheets/', '.css')
  endif

  let res = s:sub(s:findfromview('javascript_\%(include_tag\|path\|url\)\|\%(path\|url\)_to_javascript','\1'),'/defaults>','/application')
  if res != ""
    return s:findasset(res, jsext, 'public/javascripts/', '.js')
  endif

  if buffer.type_name('controller', 'mailer')
    let contr = s:controller()
    let view = s:findit('\s*\<def\s\+\(\k\+\)\>(\=','/\1')
    if view !=# ''
      let res = rails#buffer().resolve_view(contr.view)
      if res != ""|return res|endif
    endif
  endif

  let old_isfname = &isfname
  try
    set isfname=@,48-57,/,-,_,:,#
    " TODO: grab visual selection in visual mode
    let cfile = expand("<cfile>")
  finally
    let &isfname = old_isfname
  endtry
  let res = s:RailsIncludefind(cfile,1)
  return res
endfunction

function! rails#cfile(...) abort
  let cfile = s:find('find', s:cfile())[5:-1]
  return empty(cfile) && a:0 && a:1 is# 'delegate' ? "\<C-R>\<C-F>" : cfile
endfunction

function! s:app_named_route_file(route) dict abort
  call self.route_names()
  if self.cache.has("named_routes") && has_key(self.cache.get("named_routes"),a:route)
    return s:sub(self.cache.get("named_routes")[a:route].handler, '#', '_controller.rb#')
  endif
  return ""
endfunction

function! s:app_route_names() dict abort
  if self.cache.needs("named_routes")
    let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : 'cd'
    let cwd = getcwd()
    let routes = {}
    try
      execute cd fnameescape(rails#app().path())
      let output = system(self.rake_command().' routes')
    finally
      execute cd fnameescape(cwd)
    endtry
    for line in split(output, "\n")
      let matches = matchlist(line, '^ \+\(\l\w*\) \{-\}\(\u*\) \+\(\S\+\) \+\(\w\+#\w\+\)')
      if !empty(matches)
        let [_, name, method, path, handler; __] = matches
        let routes[name] = {'method': method, 'path': path, 'handler': handler}
      endif
    endfor
    call self.cache.set("named_routes",routes)
  endif

  return keys(self.cache.get("named_routes"))
endfunction

call s:add_methods('app', ['route_names','named_route_file'])

function! s:RailsIncludefind(str,...) abort
  if a:str ==# "ApplicationController" && rails#app().has_path('app/controllers/application.rb')
    return 'application.rb'
  endif
  let str = a:str
  if a:0 == 1
    " Get the text before the filename under the cursor.
    " We'll cheat and peak at this in a bit
    let line = s:linepeak()
    let line = s:sub(line,'([:"'."'".']|\%[qQ]=[[({<])=\f*$','')
  else
    let line = ""
  endif
  let str = s:sub(str,'^\s*','')
  let str = s:sub(str,'\s*$','')
  let str = s:sub(str,'^:=[:@]','')
  let str = s:sub(str,':0x\x+$','') " For #<Object:0x...> style output
  let str = s:gsub(str,"[\"']",'')
  if line =~# '\<\(require\|load\)\s*(\s*$'
    return str
  elseif str =~# '^\l\w*#\w\+$'
    return s:sub(str,'#','_controller.rb#')
  endif
  let str = rails#underscore(str)
  let fpat = '\(\s*\%("\f*"\|:\f*\|'."'\\f*'".'\)\s*,\s*\)*'
  if a:str =~# '\u' && &filetype !~# 'javascript\|coffee'
    " Classes should always be in .rb files
    let str .= '.rb'
  elseif line =~# ':partial\s*=>\s*' || (line =~# ':layout\s*=>\s*' && !rails#buffer().type_name('controller', 'mailer'))
    let str = s:sub(str,'[^/]+$','_&')
    let str = s:findview(str)
  elseif line =~# '\<layout\s*(\=\s*' || line =~# ':layout\s*=>\s*'
    let str = s:findview(s:sub(str,'^/=','layouts/'))
  elseif line =~# ':controller\s*=>\s*'
    let str = str.'_controller.rb'
  elseif line =~# '\<helper\s*(\=\s*'
    let str = str.'_helper.rb'
  elseif line =~# '\<fixtures\s*(\='.fpat
    if RailsFilePath() =~# '\<spec/'
      let str = s:sub(str,'^/@!','spec/fixtures/')
    else
      let str = s:sub(str,'^/@!','test/fixtures/')
    endif
  elseif line =~# '\<stylesheet_\(link_tag\|path\)\s*(\='.fpat
    let str = s:sub(str,'^/@!','/stylesheets/')
    if str != '' && fnamemodify(str, ':e') == ''
      let str .= '.css'
    endif
  elseif line =~# '\<javascript_\(include_tag\|path\)\s*(\='.fpat
    if str ==# "defaults"
      let str = "application"
    endif
    let str = s:sub(str,'^/@!','/javascripts/')
    if str != '' && fnamemodify(str, ':e') == ''
      let str .= '.js'
    endif
  elseif line =~# '\<\(has_one\|belongs_to\)\s*(\=\s*'
    let str = str.'.rb'
  elseif line =~# '\<has_\(and_belongs_to_\)\=many\s*(\=\s*'
    let str = rails#singularize(str).'.rb'
  elseif line =~# '\<def\s\+' && expand("%:t") =~# '_controller\.rb'
    let str = s:findview(str)
  elseif str =~# '_\%(path\|url\)$' || (line =~# ':as\s*=>\s*$' && rails#buffer().type_name('config-routes'))
    if line !~# ':as\s*=>\s*$'
      let str = s:sub(str,'_%(path|url)$','')
      let str = s:sub(str,'^hash_for_','')
    endif
    let file = rails#app().named_route_file(str)
    if file == ""
      let str = s:sub(str,'^formatted_','')
      if str =~# '^\%(new\|edit\)_'
        let str = s:sub(rails#pluralize(str),'^(new|edit)_(.*)','\2_controller.rb#\1')
      elseif str ==# rails#singularize(str)
        " If the word can't be singularized, it's probably a link to the show
        " method.  We should verify by checking for an argument, but that's
        " difficult the way things here are currently structured.
        let str = rails#pluralize(str).'_controller.rb#show'
      else
        let str = str.'_controller.rb#index'
      endif
    else
      let str = file
    endif
  elseif str !~ '/'
    " If we made it this far, we'll risk making it singular.
    let str = rails#singularize(str)
    let str = s:sub(str,'_id$','')
  endif
  if str =~ '^/' && !filereadable(str)
    let str = s:sub(str,'^/','')
  endif
  if str =~# '^lib/' && !filereadable(str)
    let str = s:sub(str,'^lib/','')
  endif
  return str
endfunction

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

function! s:addfilecmds(type)
  let l = s:sub(a:type,'^.','\l&')
  for prefix in ['E', 'S', 'V', 'T', 'D', 'R', 'RE', 'RS', 'RV', 'RT', 'RD']
    let cplt = " -complete=customlist,".s:sid.l."List"
    exe "command! -buffer -bar ".(prefix =~# 'D' ? '-range=0 ' : '')."-nargs=*".cplt." ".prefix.l." :execute s:".l.'Edit("'.(prefix =~# 'D' ? '<line1>' : '').s:sub(prefix, '^R', '').'<bang>",<f-args>)'
  endfor
endfunction

function! s:BufProjectionCommands()
  call s:addfilecmds("view")
  call s:addfilecmds("migration")
  call s:addfilecmds("schema")
  call s:addfilecmds("layout")
  call s:addfilecmds("fixtures")
  call s:addfilecmds("locale")
  if rails#app().has('spec')
    call s:addfilecmds("spec")
  endif
  call s:addfilecmds("stylesheet")
  call s:addfilecmds("javascript")
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
  if path !~ '^/' && path !~ '^\w:'
    let path = self.path(path)
  endif
  let suffix = a:0 ? a:1 : ''
  let full_paths = split(glob(path.a:glob.suffix),"\n")
  let relative_paths = []
  for entry in full_paths
    if suffix == '' && isdirectory(entry) && entry !~ '/$'
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

function! s:stylesheetList(A,L,P)
  let list = rails#app().relglob('app/assets/stylesheets/','**/*.*','')
  call map(list,'s:sub(v:val,"\\..*$","")')
  let list += rails#app().relglob('public/stylesheets/','**/*','.css')
  if rails#app().has('sass')
    call extend(list,rails#app().relglob('public/stylesheets/sass/','**/*','.s?ss'))
    call s:uniq(list)
  endif
  return s:completion_filter(list,a:A)
endfunction

function! s:javascriptList(A,L,P)
  let list = rails#app().relglob('app/assets/javascripts/','**/*.*','')
  call map(list,'s:sub(v:val,"\\.js\\..*|\\.\\w+$","")')
  let list += rails#app().relglob("public/javascripts/","**/*",".js")
  return s:completion_filter(list,a:A)
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

function! s:schemaList(A,L,P)
  let tables = s:readfile(rails#app().path('db/schema.rb'))
  let table_re = '^\s\+create_table\s["'':]\zs[^"'',]*\ze'
  call map(tables,'matchstr(v:val, table_re)')
  call filter(tables,'strlen(v:val)')
  return s:autocamelize(tables, a:A)
endfunction

function! s:specList(A,L,P)
  return s:completion_filter(rails#app().relglob("spec/","**/*","_spec.rb"),a:A)
endfunction

function! s:Navcommand(bang,...)
  let prefixes = []
  let suffix = '.rb'
  let affinity = ''
  for arg in a:000
    if arg =~# '^[a-z]\+$'
      for prefix in ['E', 'S', 'V', 'T', 'D', 'R', 'RE', 'RS', 'RV', 'RT', 'RD']
        exe 'command! -buffer -bar -bang -nargs=* ' .
              \ (prefix =~# 'D' ? '-range=0 ' : '') .
              \ prefix . arg . ' :echoerr ' .
              \ string(':Rnavcommand has been removed.  See :help rails-projections')
      endfor
      break
    endif
  endfor
endfunction

function! s:define_navcommand(name, projection, ...) abort
  if empty(a:projection)
    return
  endif
  let name = s:gsub(a:name, '[[:punct:][:space:]]', '')
  if name !~# '^[a-z]\+$'
    return s:error("E182: Invalid command name ".name)
  endif
  for prefix in ['E', 'S', 'V', 'T', 'D', 'R', 'RE', 'RS', 'RV', 'RT', 'RD']
    exe 'command! -buffer -bar -bang -nargs=* ' .
          \ (prefix =~# 'D' ? '-range=0 ' : '') .
          \ '-complete=customlist,'.s:sid.'CommandList ' .
          \ prefix . name . ' :execute s:CommandEdit(' .
          \ string((prefix =~# 'D' ? '<line1>' : '') . prefix . "<bang>") . ',' .
          \ string(a:name) . ',' . string(a:projection) . ',<f-args>)' .
          \ (a:0 ? '|' . a:1 : '')
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

function! s:LegacyCommandEdit(cmd, target, prefix, suffix)
  let cmd = s:findcmdfor(a:cmd)
  if a:target == ""
    return s:error("E471: Argument required")
  endif
  let f = a:prefix . s:sub(a:target, '\ze[#!:]|$', a:suffix)
  return s:open(a:cmd, f)
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
  let files = split(glob(self.path('db/migrate/').glob),"\n")
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
  let file = get(filter(copy(dirs), 'isdirectory(rails#app().path(v:val))'), 0, dirs[0]).'/'.c.e
  if file =~ '\.\w\+$' && rails#app().find_file(c.e, dirs) ==# ''
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

function! s:dotcmp(i1, i2)
  return strlen(s:gsub(a:i1,'[^.]', '')) - strlen(s:gsub(a:i2,'[^.]', ''))
endfunc

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

function! s:app_resolve_asset(name, ...) dict abort
  let paths = [self.path('app/assets/*'), self.path('lib/assets/*'), self.path('vendor/assets/*')]
        \ + map(copy(self.engines()), 'v:val . "/app/assets/*"')
        \ + map(values(self.gems()), 'v:val . "/vendor/assets/*"')
  let path = join(map(paths, 'escape(v:val, " ,")'), ',')
  let exact = findfile(a:name, path)
  if !empty(exact)
    return fnamemodify(exact, ':p')
  endif
  if a:0 && !empty(a:1)
    for candidate in map(split(globpath(path, a:name . '.*'), "\n"), 'fnamemodify(v:val, ":p")')
      for ext in a:1
        let pat = '[\\/]'.s:gsub(s:gsub(a:name.'.'.ext, '\.', '\\.'), '\*', '.*') . '\%(\.erb\)\=$'
        if candidate =~# pat
          return candidate
        endif
      endfor
    endfor
  endif
  return ''
endfunction

call s:add_methods('readable', ['resolve_view', 'resolve_layout'])
call s:add_methods('app', ['resolve_asset'])

function! s:findview(name) abort
  let view = rails#buffer().resolve_view(a:name, line('.'))
  return empty(view) ? a:name : view
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
  let djump = a:0 ? matchstr(a:1,'!.*\|#.*\|:\d*\ze\%(:in\)\=$') : ''
  if !empty(found)
    return s:edit(a:cmd,found.djump)
  elseif a:0 && a:1 =~# '!'
    let file = 'app/views/'.view
    if !rails#app().has_path(fnamemodify(file, ':h'))
      call mkdir(rails#app().path(fnamemodify(file, ':h')), 'p')
    endif
    return s:edit(a:cmd, file.djump)
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

function! s:stylesheetEdit(cmd,...)
  let name = a:0 ? a:1 : s:controller(1)
  if rails#app().has('sass') && rails#app().has_file('public/stylesheets/sass/'.name.'.sass')
    return s:LegacyCommandEdit(a:cmd,name,"public/stylesheets/sass/",".sass")
  elseif rails#app().has('sass') && rails#app().has_file('public/stylesheets/sass/'.name.'.scss')
    return s:LegacyCommandEdit(a:cmd,name,"public/stylesheets/sass/",".scss")
  elseif rails#app().has('lesscss') && rails#app().has_file('app/stylesheets/'.name.'.less')
    return s:LegacyCommandEdit(a:cmd,name,"app/stylesheets/",".less")
  else
    let types = rails#app().relglob('app/assets/stylesheets/'.name,'.*','')
    if !empty(types)
      return s:LegacyCommandEdit(a:cmd,name,'app/assets/stylesheets/',types[0])
    elseif !isdirectory(rails#app().path('app/assets/stylesheets'))
      return s:LegacyCommandEdit(a:cmd,name,'public/stylesheets/','.css')
    else
      return s:LegacyCommandEdit(a:cmd,name,'app/assets/stylesheets/',rails#app().stylesheet_suffix())
    endif
  endif
endfunction

function! s:javascriptEdit(cmd,...)
  let name = a:0 ? a:1 : s:controller(1)
  if rails#app().has('coffee') && rails#app().has_file('app/scripts/'.name.'.coffee')
    return s:LegacyCommandEdit(a:cmd,name,'app/scripts/','.coffee')
  elseif rails#app().has('coffee') && rails#app().has_file('app/scripts/'.name.'.js')
    return s:LegacyCommandEdit(a:cmd,name,'app/scripts/','.js')
  else
    let types = rails#app().relglob('app/assets/javascripts/'.name,'.*','')
    if !empty(types)
      return s:LegacyCommandEdit(a:cmd,name,'app/assets/javascripts/',types[0])
    elseif !isdirectory(rails#app().path('app/assets/javascripts'))
      return s:LegacyCommandEdit(a:cmd,name,'public/javascripts/','.js')
    elseif rails#app().has_gem('coffee-rails')
      return s:LegacyCommandEdit(a:cmd,name,'app/assets/javascripts/','.coffee')
    else
      return s:LegacyCommandEdit(a:cmd,name,'app/assets/javascripts/','.js')
    endif
  endif
endfunction

function! s:specEdit(cmd,...) abort
  let describe = s:sub(s:sub(rails#camelize(a:0 ? a:1 : ''), '^[^:]*::', ''), '!.*', '')
  return rails#buffer().open_command(a:cmd, a:0 ? a:1 : '', 'spec', [
        \ {'pattern': 'spec/*_spec.rb', 'template': "require 'spec_helper'\n\ndescribe ".describe." do\nend"},
        \ {'pattern': 'spec/spec_helper.rb'}])
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
  if cmd =~ '^\d'
    let num = matchstr(cmd,'^\d\+')
    let cmd = s:sub(cmd,'^\d+','')
  else
    let num = ''
  endif
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

function! s:r_warning(cmd) abort
  if a:cmd =~# 'R\|^$'
    let old = s:sub(a:cmd, '^$', 'R')
    let instead = s:sub(s:sub(a:cmd, '^R', ''), '^$', 'E')
    return '|echohl WarningMsg|echomsg ":'.old.' navigation commands are deprecated. Use :'.instead.' commands instead."|echohl None'
  endif
  return ''
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
      return cmd . ' ' . s:jumpargs(file, djump) . s:r_warning(a:cmd)
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
      if !isdirectory(fnamemodify(file, ':h'))
        call mkdir(fnamemodify(file, ':h'), 'p')
      endif
      if has_key(projection, 'template')
        let template = s:split(projection.template)
        let ph = {
              \ 'match': root,
              \ 'file': file,
              \ 'project': self.app().path(),
              \ 'S': rails#camelize(root),
              \ 'h': toupper(root[0]) . tr(rails#underscore(root), '_', ' ')[1:-1]}
        call map(template, 's:expand_placeholders(v:val, ph)')
        call map(template, 's:gsub(v:val, "\t", "  ")')
        let file = fnamemodify(simplify(file), ':.')
        return cmd . ' ' . s:fnameescape(file) . '|call setline(1, '.string(template).')' . '|set nomod'.s:r_warning(a:cmd)
      else
        return cmd . ' +AD ' . s:fnameescape(file) . s:r_warning(a:cmd)
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
    let file = simplify(rails#app().path() . s:sub(file[1:-1], '^\.', '/..'))
  endif
  let cmd = (empty(a:cmd) ? '' : s:findcmdfor(a:cmd)) . ' '
  if djump =~# '!'
    if !isdirectory(fnamemodify(file, ':h'))
      call mkdir(fnamemodify(file, ':h'), 'p')
    endif
    return s:editcmdfor(cmd) . s:jumpargs(fnamemodify(file, ':~:.'), djump)
  else
    return cmd . s:jumpargs(file, djump)
  endif
endfunction

function! s:open(cmd, file) abort
  return s:find(a:cmd, rails#app().path(a:file))
endfunction

function! s:edit(cmd, file) abort
  return s:open(s:editcmdfor(a:cmd), a:file)
endfunction

function! s:Alternate(cmd,line1,line2,count,...) abort
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
      let tail = matchstr(file,'[#!].*$\|:\d*\%(:in\>.*\)\=$')
      if tail != ""
        let file = s:sub(file,'[#!].*$|:\d*%(:in>.*)=$','')
      endif
      if file != ""
        let file = s:RailsIncludefind(file)
      endif
      return s:find(a:cmd . cmd, file . tail)
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
      if !modified && !filereadable(expand('%'))
        setlocal nomodified
      endif
    endif
    return ''
  else
    let file = get(b:, a:count ? 'rails_related' : 'rails_alternate')
    if empty(file)
      let file = rails#buffer().alternate(a:count)
    endif
    let has_path = !empty(file) && rails#app().has_path(file)
    let confirm = &confirm || (histget(':', -1) =~# '\%(^\||\)\s*conf\%[irm]\>')
    if confirm && !a:count && !has_path
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

function! s:Related(cmd,line1,line2,count,...)
  if a:count == 0 && a:0 == 0
    return s:Alternate(a:cmd,a:line1,a:line1,a:line1)
  else
    return call('s:Alternate',[a:cmd,a:line1,a:line2,a:count]+a:000)
  endif
endfunction

function! s:Complete_related(A,L,P)
  if a:L =~# '^[[:alpha:]]' || a:A =~# '^\w*:\|^\.\=[\/]'
    return s:Complete_edit(a:A,a:L,a:P)
  else
    return s:Complete_find(a:A,a:L,a:P)
  endif
endfunction

function! s:readable_alternate_candidates(...) dict abort
  let f = self.name()
  let placeholders = {}
  if a:0 && a:1
    let placeholders.lnum = a:1
    let placeholders.line = a:1
    let lastmethod = self.last_method(a:1)
    if !empty(lastmethod)
      let placeholders.d = lastmethod
      let placeholders.define = lastmethod
    endif
    let projected = self.projected('related', placeholders)
    if !empty(projected)
      return projected
    endif
    if self.type_name('controller','mailer') && lastmethod != ""
      let view = self.resolve_view(lastmethod, line('.'))
      if view !=# ''
        return [view]
      else
        return [s:sub(s:sub(s:sub(f,'/application%(_controller)=\.rb$','/shared_controller.rb'),'/%(controllers|models|mailers)/','/views/'),'%(_controller)=\.rb$','/'.lastmethod)]
      endif
    elseif f =~# '^config/environments/'
      return ['config/database.yml#'. fnamemodify(f,':t:r')]
    elseif f ==# 'config/database.yml'
      if lastmethod != ""
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
      return [controller, controller2, mailer, model]
    elseif self.type_name('controller')
      return [s:sub(s:sub(f,'/controllers/','/helpers/'),'%(_controller)=\.rb$','_helper.rb')]
    elseif self.type_name('model-record')
      let table_name = matchstr(join(self.getline(1,50),"\n"),'\n\s*self\.table_name\s*=\s*[:"'']\zs\w\+')
      if table_name == ''
        let table_name = rails#pluralize(s:gsub(s:sub(fnamemodify(f,':r'),'.{-}<app/models/',''),'/','_'))
      endif
      return ['db/schema.rb#'.table_name]
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
    if !exists('lastmethod') || lastmethod == 'down' || (a:0 && a:1 == 1)
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
    if f =~ 'public/javascripts'
      let to_replace = 'public/javascripts'
    else
      let to_replace = 'app/assets/javascripts'
    endif
    if f =~ '.coffee.js$'
      let suffix = '.coffee.js'
      let suffix_replacement = '_spec.coffee.js'
    elseif f =~ '.coffee$'
      let suffix = '.coffee'
      let suffix_replacement = '_spec.coffee'
    elseif f =~ '[A-Z][a-z]\+\.js$'
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

function! s:Extract(bang,...) range abort
  if a:0 == 0 || a:0 > 1
    return s:error("Incorrect number of arguments")
  endif
  if a:1 =~ '[^a-z0-9_/.]'
    return s:error("Invalid partial name")
  endif
  let rails_root = rails#app().path()
  let ext = expand("%:e")
  let file = s:sub(a:1,'%(/|^)\zs_\ze[^/]*$','')
  let first = a:firstline
  let last = a:lastline
  let range = first.",".last
  if rails#buffer().type_name('view-layout')
    if RailsFilePath() =~ '\<app/views/layouts/application\>'
      let curdir = 'app/views/shared'
      if file !~ '/'
        let file = "shared/" .file
      endif
    else
      let curdir = s:sub(RailsFilePath(),'.*<app/views/layouts/(.*)%(\.\w*)$','app/views/\1')
    endif
  else
    let curdir = fnamemodify(RailsFilePath(),':h')
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
  elseif isdirectory(curdir."/".dir)
    let out = (curdir)."/".dir."/_".fname
  else
    let out = (rails_root)."/app/views/".dir."/_".fname
  endif
  if filereadable(out) && !a:bang
    return s:error('E13: File exists (add ! to override)')
  endif
  if !isdirectory(fnamemodify(out,':h'))
    if a:bang
      call mkdir(fnamemodify(out,':h'),'p')
    else
      return s:error('No such directory')
    endif
  endif
  if ext =~? '^\%(rhtml\|erb\|dryml\)$'
    let erub1 = '\<\%\s*'
    let erub2 = '\s*-=\%\>'
  else
    let erub1 = ''
    let erub2 = ''
  endif
  let spaces = matchstr(getline(first),"^ *")
  let renderstr = 'render "'.fnamemodify(file,":r:r").'"'
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
  let buf = @@
  silent exe range."yank"
  let partial = @@
  let @@ = buf
  let old_ai = &ai
  try
    let &ai = 0
    silent exe "norm! :".first.",".last."change\<CR>".spaces.renderstr."\<CR>.\<CR>"
  finally
    let &ai = old_ai
  endtry
  if renderstr =~ '<%'
    norm ^6w
  else
    norm ^5w
  endif
  let ft = &ft
  let shortout = fnamemodify(out,':.')
  silent execute 'split '.s:fnameescape(shortout)
  silent %delete _
  let &ft = ft
  let @@ = partial
  silent put
  0delete
  let @@ = buf
  if spaces != ""
    silent! exe '%substitute/^'.spaces.'//'
  endif
  1
endfunction

function! s:RubyExtract(bang, root, before, name) range abort
  let content = getline(a:firstline, a:lastline)
  execute a:firstline.','.a:lastline.'delete_'
  let indent = get(sort(map(filter(copy(content), '!empty(v:val)'), 'len(matchstr(v:val, "^ \\+"))')), 0, 0)
  if indent
    call map(content, 's:sub(v:val, "^".repeat(" ", indent), "  ")')
  endif
  call append(a:firstline-1, repeat(' ', indent).'include '.rails#camelize(a:name))
  let out = rails#app().path(a:root, a:name . '.rb')
  if filereadable(out) && !a:bang
    return s:error('E13: File exists (add ! to override)')
  endif
  if !isdirectory(fnamemodify(out, ':h'))
    call mkdir(fnamemodify(out, ':h'), 'p')
  endif
  execute 'split '.s:fnameescape(out)
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
  if exists('b:rails_root')
    return call(rails#app().cache.clear,a:000,rails#app().cache)
  endif
endfunction

function! s:cache_get(...) dict
  if a:0 == 1
    return self.dict[a:1]
  else
    return self.dict
  endif
endfunction

function! s:cache_has(key) dict
  return has_key(self.dict,a:key)
endfunction

function! s:cache_needs(key) dict
  return !has_key(self.dict,a:key)
endfunction

function! s:cache_set(key,value) dict
  let self.dict[a:key] = a:value
endfunction

call s:add_methods('cache', ['clear','needs','has','get','set'])

let s:app_prototype.cache = s:cache_prototype

" }}}1
" Syntax {{{1

function! s:resetomnicomplete()
  if exists("+completefunc") && &completefunc == 'syntaxcomplete#Complete'
    if exists("g:loaded_syntax_completion")
      " Ugly but necessary, until we have our own completion
      unlet g:loaded_syntax_completion
      silent! delfunction syntaxcomplete#Complete
    endif
  endif
endfunction

function! s:helpermethods()
  return ""
        \."action_name asset_path asset_url atom_feed audio_path audio_tag audio_url auto_discovery_link_tag "
        \."button_tag button_to "
        \."cache cache_fragment_name cache_if cache_unless capture cdata_section check_box check_box_tag collection_check_boxes collection_radio_buttons collection_select color_field color_field_tag compute_asset_extname compute_asset_host compute_asset_path concat content_for content_tag content_tag_for controller controller_name controller_path convert_to_model cookies csrf_meta_tag csrf_meta_tags current_cycle cycle action_cable_meta_tag "
        \."date_field date_field_tag date_select datetime_field datetime_field_tag datetime_local_field datetime_local_field_tag datetime_select debug distance_of_time_in_words distance_of_time_in_words_to_now div_for dom_class dom_id "
        \."email_field email_field_tag escape_javascript escape_once excerpt "
        \."favicon_link_tag field_set_tag fields_for file_field file_field_tag flash font_path font_url form_for form_tag "
        \."grouped_collection_select grouped_options_for_select "
        \."headers hidden_field hidden_field_tag highlight "
        \."image_alt image_path image_submit_tag image_tag image_url "
        \."j javascript_cdata_section javascript_include_tag javascript_path javascript_tag javascript_url "
        \."l label label_tag link_to link_to_if link_to_unless link_to_unless_current localize logger "
        \."mail_to month_field month_field_tag "
        \."number_field number_field_tag number_to_currency number_to_human number_to_human_size number_to_percentage number_to_phone number_with_delimiter number_with_precision "
        \."option_groups_from_collection_for_select options_for_select options_from_collection_for_select "
        \."params password_field password_field_tag path_to_asset path_to_audio path_to_font path_to_image path_to_javascript path_to_stylesheet path_to_video phone_field phone_field_tag pluralize provide "
        \."radio_button radio_button_tag range_field range_field_tag raw render request request_forgery_protection_token reset_cycle response "
        \."safe_concat safe_join sanitize sanitize_css search_field search_field_tag select select_date select_datetime select_day select_hour select_minute select_month select_second select_tag select_time select_year session simple_format strip_links strip_tags stylesheet_link_tag stylesheet_path stylesheet_url submit_tag "
        \."t tag telephone_field telephone_field_tag text_area text_area_tag text_field text_field_tag time_ago_in_words time_field time_field_tag time_select time_tag time_zone_options_for_select time_zone_select translate truncate "
        \."url_field url_field_tag url_for url_to_asset url_to_audio url_to_font url_to_image url_to_javascript url_to_stylesheet url_to_video utf8_enforcer_tag "
        \."video_path video_tag video_url "
        \."week_field week_field_tag word_wrap"
endfunction

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

function! rails#buffer_syntax()
  if !exists("g:rails_no_syntax")
    let buffer = rails#buffer()
    let keywords = split(join(buffer.projected('keywords'), ' '))
    let special = filter(copy(keywords), 'v:val =~# ''^\h\k*[?!]$''')
    let regular = filter(copy(keywords), 'v:val =~# ''^\h\k*$''')
    if &syntax == 'ruby'
      if !empty(special)
        exe 'syn match rubyRailsMethod "\<\%('.join(special, '\|').'\)"'
      endif
      if !empty(regular)
        exe 'syn keyword rubyRailsMethod '.join(regular, ' ')
      endif
      if buffer.type_name() == ''
        syn keyword rubyRailsMethod params request response session headers cookies flash
      endif
      if buffer.type_name() ==# 'model' || buffer.type_name('model-record')
        syn keyword rubyRailsARMethod default_scope enum named_scope scope serialize store
        syn keyword rubyRailsARAssociationMethod belongs_to has_one has_many has_and_belongs_to_many composed_of accepts_nested_attributes_for
        syn keyword rubyRailsARCallbackMethod before_create before_destroy before_save before_update before_validation before_validation_on_create before_validation_on_update before_commit
        syn keyword rubyRailsARCallbackMethod after_create after_destroy after_save after_update after_validation after_validation_on_create after_validation_on_update after_create_commit after_update_commit after_destroy_commit
        syn keyword rubyRailsARCallbackMethod around_create around_destroy around_save around_update
        syn keyword rubyRailsARCallbackMethod after_commit after_find after_initialize after_rollback after_touch
        syn keyword rubyRailsARClassMethod attr_accessible attr_protected attr_readonly has_secure_password has_secure_token store_accessor
        syn keyword rubyRailsARValidationMethod validate validates validate_on_create validate_on_update validates_acceptance_of validates_associated validates_confirmation_of validates_each validates_exclusion_of validates_format_of validates_inclusion_of validates_length_of validates_numericality_of validates_presence_of validates_absence_of validates_size_of validates_uniqueness_of validates_with
        syn keyword rubyRailsMethod logger
      endif
      if buffer.type_name('model-observer')
        syn keyword rubyRailsARMethod observe
      endif
      if buffer.type_name('mailer')
        syn keyword rubyRailsMethod logger url_for polymorphic_path polymorphic_url
        syn keyword rubyRailsRenderMethod mail render
        syn keyword rubyRailsControllerMethod attachments default helper helper_attr helper_method layout
      endif
      if buffer.type_name('job')
        syn keyword rubyRailsAPIMethod queue_as rescue_from
        syn keyword rubyRailsARCallbackMethod before_enqueue around_enqueue after_enqueue before_perform around_perform after_perform
      endif
      if buffer.type_name('helper','view')
        syn keyword rubyRailsViewMethod polymorphic_path polymorphic_url
        exe "syn keyword rubyRailsHelperMethod ".s:gsub(s:helpermethods(),'<%(content_for|select)\s+','')
        syn match rubyRailsHelperMethod '\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!'
        syn match rubyRailsHelperMethod '\<\%(content_for?\=\|current_page?\)'
        syn match rubyRailsViewMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>'
        if buffer.type_name('view-partial')
          syn keyword rubyRailsMethod local_assigns
        endif
      elseif buffer.type_name('controller')
        syn keyword rubyRailsMethod params request response session headers cookies flash
        syn keyword rubyRailsRenderMethod render
        syn keyword rubyRailsMethod logger polymorphic_path polymorphic_url
        syn keyword rubyRailsControllerMethod helper helper_attr helper_method filter layout url_for serialize exempt_from_layout filter_parameter_logging hide_action cache_sweeper protect_from_forgery caches_page cache_page caches_action expire_page expire_action rescue_from
        syn keyword rubyRailsRenderMethod head redirect_to redirect_back render_to_string respond_with
        syn match   rubyRailsRenderMethod '\<respond_to\>?\@!'
        syn keyword rubyRailsFilterMethod before_filter append_before_filter prepend_before_filter after_filter append_after_filter prepend_after_filter around_filter append_around_filter prepend_around_filter skip_before_filter skip_after_filter skip_filter before_action append_before_action prepend_before_action after_action append_after_action prepend_after_action around_action append_around_action prepend_around_action skip_before_action skip_after_action skip_action
        syn keyword rubyRailsFilterMethod verify
      endif
      if buffer.type_name('db-migration','db-schema')
        syn keyword rubyRailsMigrationMethod create_table change_table drop_table rename_table create_join_table drop_join_table
        syn keyword rubyRailsMigrationMethod add_column rename_column change_column change_column_default change_column_null remove_column remove_columns
        syn keyword rubyRailsMigrationMethod add_foreign_key remove_foreign_key
        syn keyword rubyRailsMigrationMethod add_timestamps remove_timestamps
        syn keyword rubyRailsMigrationMethod add_reference remove_reference add_belongs_to remove_belongs_to
        syn keyword rubyRailsMigrationMethod add_index remove_index rename_index
        syn keyword rubyRailsMigrationMethod execute transaction reversible revert
      endif
      if buffer.type_name('test')
        if !empty(rails#app().user_assertions())
          exe "syn keyword rubyRailsUserMethod ".join(rails#app().user_assertions())
        endif
        syn keyword rubyRailsTestMethod refute refute_empty refute_equal refute_in_delta refute_in_epsilon refute_includes refute_instance_of refute_kind_of refute_match refute_nil refute_operator refute_predicate refute_respond_to refute_same
        syn keyword rubyRailsTestMethod add_assertion assert assert_block assert_equal assert_includes assert_in_delta assert_instance_of assert_kind_of assert_match assert_nil assert_no_match assert_not assert_not_equal assert_not_nil assert_not_same assert_nothing_raised assert_nothing_thrown assert_operator assert_raise assert_respond_to assert_same assert_send assert_throws assert_recognizes assert_generates assert_routing flunk fixtures fixture_path use_transactional_fixtures use_instantiated_fixtures assert_difference assert_no_difference assert_valid
        syn keyword rubyRailsTestMethod test setup teardown
        if !buffer.type_name('test-unit')
          syn match   rubyRailsTestControllerMethod  '\.\@<!\<\%(get\|post\|put\|patch\|delete\|head\|process\|assigns\)\>'
          syn keyword rubyRailsTestControllerMethod get_via_redirect post_via_redirect put_via_redirect delete_via_redirect request_via_redirect
          syn keyword rubyRailsTestControllerMethod assert_response assert_redirected_to assert_template assert_recognizes assert_generates assert_routing assert_dom_equal assert_dom_not_equal assert_select assert_select_rjs assert_select_encoded assert_select_email assert_tag assert_no_tag
        endif
      elseif buffer.type_name('spec')
        syn keyword rubyRailsTestMethod describe context it its specify shared_context shared_examples shared_examples_for shared_context include_examples include_context it_should_behave_like it_behaves_like before after around subject fixtures controller_name helper_name scenario feature background given described_class
        syn match rubyRailsTestMethod '\<let\>!\='
        syn keyword rubyRailsTestMethod violated pending expect expect_any_instance_of allow allow_any_instance_of double instance_double mock mock_model stub_model xit
        syn match rubyRailsTestMethod '\.\@<!\<stub\>!\@!'
        if !buffer.type_name('spec-model')
          syn match   rubyRailsTestControllerMethod  '\.\@<!\<\%(get\|post\|put\|patch\|delete\|head\|process\|assigns\)\>'
          syn keyword rubyRailsTestControllerMethod  integrate_views render_views
          syn keyword rubyRailsMethod params request response session flash
          syn keyword rubyRailsMethod polymorphic_path polymorphic_url
          if buffer.type_name('spec-view')
            syn keyword rubyRailsTestViewMethod render rendered assign
          elseif buffer.type_name('spec-helper')
            syn keyword RubyRailsTestHelperMethod helper
          endif
        endif
      endif
      if buffer.type_name('task')
        syn match rubyRailsRakeMethod '^\s*\zs\%(task\|file\|namespace\|desc\|before\|after\|on\)\>\%(\s*=\)\@!'
      endif
      if buffer.type_name('config-routes')
        syn match rubyRailsMethod '\.\zs\%(connect\|named_route\)\>'
        syn keyword rubyRailsMethod match get put patch post delete redirect root resource resources collection member nested scope namespace controller constraints mount concern concerns
      endif
      syn keyword rubyRailsMethod debugger
      syn keyword rubyRailsMethod alias_attribute alias_method_chain attr_accessor_with_default attr_internal attr_internal_accessor attr_internal_reader attr_internal_writer concerning delegate mattr_accessor mattr_reader mattr_writer superclass_delegating_accessor superclass_delegating_reader superclass_delegating_writer with_options
      syn keyword rubyRailsMethod cattr_accessor cattr_reader cattr_writer class_inheritable_accessor class_inheritable_array class_inheritable_array_writer class_inheritable_hash class_inheritable_hash_writer class_inheritable_option class_inheritable_reader class_inheritable_writer inheritable_attributes read_inheritable_attribute reset_inheritable_attributes write_inheritable_array write_inheritable_attribute write_inheritable_hash
      syn keyword rubyRailsInclude require_dependency

      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:order\s*=>\s*\)\@<="+ skip=+\\\\\|\\"+ end=+"+ contains=@rubyStringSpecial,railsOrderSpecial
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:order\s*=>\s*\)\@<='+ skip=+\\\\\|\\'+ end=+'+ contains=@rubyStringSpecial,railsOrderSpecial
      syn match   railsOrderSpecial +\c\<\%(DE\|A\)SC\>+ contained
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:conditions\s*=>\s*\[\s*\)\@<="+ skip=+\\\\\|\\"+ end=+"+ contains=@rubyStringSpecial,railsConditionsSpecial
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:conditions\s*=>\s*\[\s*\)\@<='+ skip=+\\\\\|\\'+ end=+'+ contains=@rubyStringSpecial,railsConditionsSpecial
      syn match   railsConditionsSpecial +?\|:\h\w*+ contained
      syn cluster rubyNotTop add=railsOrderSpecial,railsConditionsSpecial

    elseif &syntax =~# '^eruby\>' || &syntax == 'haml'
      let containedin = 'contained containedin=@'.&syntax.'RailsRegions'
      syn case match
      if !empty(special)
        exe 'syn match '.&syntax.'RailsMethod "\<\%('.join(special, '\|').'\)"' containedin
      endif
      if !empty(regular)
        exe 'syn keyword '.&syntax.'RailsMethod '.join(regular, ' ') containedin
      endif
      if &syntax == 'haml'
        exe 'syn cluster hamlRailsRegions contains=hamlRubyCodeIncluded,hamlRubyCode,hamlRubyHash,@hamlEmbeddedRuby,rubyInterpolation'
      else
        exe 'syn cluster erubyRailsRegions contains=erubyOneLiner,erubyBlock,erubyExpression,rubyInterpolation'
      endif
      exe 'syn keyword '.&syntax.'RailsHelperMethod '.s:gsub(s:helpermethods(),'<%(content_for|select)\s+','').' contained containedin=@'.&syntax.'RailsRegions'
      exe 'syn match '.&syntax.'RailsHelperMethod "\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!" contained containedin=@'.&syntax.'RailsRegions'
      exe 'syn match '.&syntax.'RailsHelperMethod "\<\%(content_for?\=\|current_page?\)" contained containedin=@'.&syntax.'RailsRegions'
      exe 'syn keyword '.&syntax.'RailsMethod debugger polymorphic_path polymorphic_url contained containedin=@'.&syntax.'RailsRegions'
      exe 'syn match '.&syntax.'RailsViewMethod "\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>" contained containedin=@'.&syntax.'RailsRegions'
      if buffer.type_name('view-partial')
        exe 'syn keyword '.&syntax.'RailsMethod local_assigns contained containedin=@'.&syntax.'RailsRegions'
      endif
      exe 'syn keyword '.&syntax.'RailsRenderMethod render contained containedin=@'.&syntax.'RailsRegions'
      exe 'syn case match'
    elseif &syntax == "yaml"
      syn case match
      unlet! b:current_syntax
      let g:main_syntax = 'eruby'
      syn include @rubyTop syntax/ruby.vim
      unlet g:main_syntax
      syn cluster yamlRailsRegions contains=yamlRailsOneLiner,yamlRailsBlock,yamlRailsExpression
      syn region  yamlRailsOneLiner   matchgroup=yamlRailsDelimiter start="^%%\@!" end="$"  contains=@rubyRailsTop      containedin=ALLBUT,@yamlRailsRegions,yamlRailsComment keepend oneline
      syn region  yamlRailsBlock      matchgroup=yamlRailsDelimiter start="<%%\@!" end="%>" contains=@rubyTop           containedin=ALLBUT,@yamlRailsRegions,yamlRailsComment
      syn region  yamlRailsExpression matchgroup=yamlRailsDelimiter start="<%="    end="%>" contains=@rubyTop           containedin=ALLBUT,@yamlRailsRegions,yamlRailsComment
      syn region  yamlRailsComment    matchgroup=yamlRailsDelimiter start="<%#"    end="%>" contains=rubyTodo,@Spell    containedin=ALLBUT,@yamlRailsRegions,yamlRailsComment keepend
      syn match yamlRailsMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' contained containedin=@yamlRailsRegions
      let b:current_syntax = "yaml"

    elseif &syntax == "scss" || &syntax == "sass"
      syn match sassFunction "\<\%(\%(asset\|image\|font\|video\|audio\|javascript\|stylesheet\)-\%(url\|path\)\)\>(\@=" contained
      syn match sassFunction "\<\asset-data-url\>(\@=" contained
    endif
  endif
  call s:HiDefaults()
endfunction

function! s:HiDefaults()
  hi def link rubyRailsAPIMethod              rubyRailsMethod
  hi def link rubyRailsARAssociationMethod    rubyRailsARMethod
  hi def link rubyRailsARCallbackMethod       rubyRailsARMethod
  hi def link rubyRailsARClassMethod          rubyRailsARMethod
  hi def link rubyRailsARValidationMethod     rubyRailsARMethod
  hi def link rubyRailsARMethod               rubyRailsMethod
  hi def link rubyRailsRenderMethod           rubyRailsMethod
  hi def link rubyRailsHelperMethod           rubyRailsMethod
  hi def link rubyRailsViewMethod             rubyRailsMethod
  hi def link rubyRailsMigrationMethod        rubyRailsMethod
  hi def link rubyRailsControllerMethod       rubyRailsMethod
  hi def link rubyRailsFilterMethod           rubyRailsMethod
  hi def link rubyRailsTestControllerMethod   rubyRailsTestMethod
  hi def link rubyRailsTestViewMethod         rubyRailsTestMethod
  hi def link rubyRailsTestHelperMethod       rubyRailsTestMethod
  hi def link rubyRailsTestMethod             rubyRailsMethod
  hi def link rubyRailsRakeMethod             rubyRailsMethod
  hi def link rubyRailsMethod                 railsMethod
  hi def link rubyRailsInclude                rubyInclude
  hi def link rubyRailsUserClass              railsUserClass
  hi def link rubyRailsUserMethod             railsUserMethod
  hi def link erubyRailsHelperMethod          erubyRailsMethod
  hi def link erubyRailsViewMethod            erubyRailsMethod
  hi def link erubyRailsRenderMethod          erubyRailsMethod
  hi def link erubyRailsMethod                railsMethod
  hi def link erubyRailsUserMethod            railsUserMethod
  hi def link erubyRailsUserClass             railsUserClass
  hi def link hamlRailsHelperMethod           hamlRailsMethod
  hi def link hamlRailsViewMethod             hamlRailsMethod
  hi def link hamlRailsRenderMethod           hamlRailsMethod
  hi def link hamlRailsMethod                 railsMethod
  hi def link hamlRailsUserMethod             railsUserMethod
  hi def link hamlRailsUserClass              railsUserClass
  hi def link railsUserMethod                 railsMethod
  hi def link yamlRailsDelimiter              Delimiter
  hi def link yamlRailsMethod                 railsMethod
  hi def link yamlRailsComment                Comment
  hi def link yamlRailsUserClass              railsUserClass
  hi def link yamlRailsUserMethod             railsUserMethod
  hi def link javascriptRailsFunction         railsMethod
  hi def link railsUserClass                  railsClass
  hi def link railsMethod                     Function
  hi def link railsClass                      Type
  hi def link railsOrderSpecial               railsStringSpecial
  hi def link railsConditionsSpecial          railsStringSpecial
  hi def link railsStringSpecial              Identifier
endfunction

function! rails#log_syntax()
  if has('conceal')
    syn match railslogEscape      '\e\[[0-9;]*m' conceal
    syn match railslogEscapeMN    '\e\[[0-9;]*m' conceal nextgroup=railslogModelNum,railslogEscapeMN skipwhite contained
  else
    syn match railslogEscape      '\e\[[0-9;]*m'
    syn match railslogEscapeMN    '\e\[[0-9;]*m' nextgroup=railslogModelNum,railslogEscapeMN skipwhite contained
  endif
  syn match   railslogRender      '\%(^\s*\%(\e\[[0-9;]*m\)\=\)\@<=\%(Started\|Processing\|Rendering\|Rendered\|Redirected\|Completed\)\>'
  syn match   railslogComment     '^\s*# .*'
  syn match   railslogModel       '\%(^\s*\%(\e\[[0-9;]*m\)*\)\@<=\u\%(\w\|:\)* \%(Load\%( Including Associations\| IDs For Limited Eager Loading\)\=\|Columns\|Exists\|Count\|Create\|Update\|Destroy\|Delete all\)\>' skipwhite nextgroup=railslogModelNum,railslogEscapeMN
  syn match   railslogModel       '\%(^\s*\%(\e\[[0-9;]*m\)*\)\@<=\%(SQL\|CACHE\)\>' skipwhite nextgroup=railslogModelNum,railslogEscapeMN
  syn region  railslogModelNum    start='(' end=')' contains=railslogNumber contained skipwhite
  syn match   railslogNumber      '\<\d\+\>%'
  syn match   railslogNumber      '[ (]\@<=\<\d\+\.\d\+\>\.\@!'
  syn match   railslogNumber      '[ (]\@<=\<\d\+\.\d\+ms\>'
  syn region  railslogString      start='"' skip='\\"' end='"' oneline contained
  syn region  railslogHash        start='{' end='}' oneline contains=railslogHash,railslogString
  syn match   railslogIP          '\<\d\{1,3\}\%(\.\d\{1,3}\)\{3\}\>'
  syn match   railslogTimestamp   '\<\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\>'
  syn match   railslogSessionID   '\<\x\{32\}\>'
  syn match   railslogIdentifier  '^\s*\%(Session ID\|Parameters\|Unpermitted parameters\)\ze:'
  syn match   railslogSuccess     '\<2\d\d \u[A-Za-z0-9 ]*\>'
  syn match   railslogRedirect    '\<3\d\d \u[A-Za-z0-9 ]*\>'
  syn match   railslogError       '\<[45]\d\d \u[A-Za-z0-9 ]*\>'
  syn match   railslogError       '^DEPRECATION WARNING\>'
  syn keyword railslogHTTP        OPTIONS GET HEAD POST PUT PATCH DELETE TRACE CONNECT
  hi def link railslogEscapeMN    railslogEscape
  hi def link railslogEscape      Ignore
  hi def link railslogComment     Comment
  hi def link railslogRender      Keyword
  hi def link railslogModel       Type
  hi def link railslogNumber      Number
  hi def link railslogString      String
  hi def link railslogSessionID   Constant
  hi def link railslogIdentifier  Identifier
  hi def link railslogRedirect    railslogSuccess
  hi def link railslogSuccess     Special
  hi def link railslogError       Error
  hi def link railslogHTTP        Special
endfunction

function! rails#log_setup() abort
  nnoremap <buffer> <silent> R :checktime<CR>
  nnoremap <buffer> <silent> G :checktime<Bar>$<CR>
  nnoremap <buffer> <silent> q :bwipe<CR>
  setlocal modifiable noswapfile autoread
  if exists('+concealcursor')
    setlocal concealcursor=nc conceallevel=2
  else
    silent %s/\%(\e\[[0-9;]*m\|\r$\)//ge
  endif
  setlocal readonly nomodifiable
  $
endfunction

" }}}1
" Mappings {{{1

nnoremap <SID>: :<C-U><C-R>=v:count ? v:count : ''<CR>
function! s:BufMappings() abort
  cmap <buffer><script><expr> <Plug><cfile>   rails#cfile('delegate')
  nmap <buffer><silent> <Plug>RailsFind       <SID>:find <Plug><cfile><CR>
  nmap <buffer><silent> <Plug>RailsSplitFind  <SID>:sfind <Plug><cfile><CR>
  nmap <buffer><silent> <Plug>RailsTabFind    <SID>:tabfind <Plug><cfile><CR>
  let pattern = '^$\|_gf(v:count\|[Rr]uby\|[Rr]ails'
  if mapcheck('gf', 'n') =~# pattern
    nmap <buffer> gf         <Plug>RailsFind
  endif
  if mapcheck('<C-W>f', 'n') =~# pattern
    nmap <buffer> <C-W>f     <Plug>RailsSplitFind
  endif
  if mapcheck('<C-W><C-F>', 'n') =~# pattern
    nmap <buffer> <C-W><C-F> <Plug>RailsSplitFind
  endif
  if mapcheck('<C-W>gf', 'n') =~# pattern
    nmap <buffer> <C-W>gf    <Plug>RailsTabFind
  endif
  if mapcheck('<C-R><C-F>', 'c') =~# pattern
    cmap <buffer> <C-R><C-F> <Plug><cfile>
  endif
endfunction

" }}}1
" Database {{{1

function! rails#yaml_parse_file(file) abort
  let json = system('ruby -e '.s:rquote('require %{yaml}; require %{json}; File.open(%q{'.a:file.'}) {|f| puts JSON.generate(YAML::load(f))}'))
  if !v:shell_error && json =~# '^[[{]'
    return rails#json_parse(json)
  endif
  throw 'invalid YAML file: '.a:file
endfunction

function! s:app_db_config(environment) dict
  let all = {}
  if self.cache.has('db_config')
    let all = self.cache.get('db_config')
  elseif self.has_path('config/database.yml')
    try
      let all = rails#yaml_parse_file(self.path('config/database.yml'))
      call self.cache.set('db_config', all)
    catch /^invalid/
    endtry
  endif
  if has_key(all, a:environment)
    return all[a:environment]
  elseif self.has_gem('rails-default-database')
    let db = s:gsub(fnamemodify(self.path(), ':t'), '[^[:alnum:]]+', '_') .
          \ '_' . a:environment
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
  return substitute(a:str, '[?@=&<>%#[:space:]' . (a:0 && a:1 == 'path' ? '' : ':/').']', '\=printf("%%%02X", char2nr(submatch(0)))', 'g')
endfunction

function! s:app_db_url(...) dict abort
  let env = a:0 ? a:1 : s:environment()
  if self.has_gem('dotenv') && filereadable(self.path('.env'))
    for line in readfile(self.path('.env'))
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

function! s:app_dbext_settings(environment) dict abort
  let config = self.db_config(a:environment)
  if has_key(config, 'adapter')
    let dict = {}
    let adapter = config.adapter
    let adapter = get({
          \ 'mysql2': 'mysql',
          \ 'postgresql': 'pgsql',
          \ 'sqlite3': 'sqlite',
          \ 'sqlserver': 'sqlsrv',
          \ 'sybase': 'asa',
          \ 'oracle': 'ora',
          \ 'oracle_enhanced': 'ora'},
          \ adapter, adapter)
    let dict.type = toupper(adapter)
    let dict.user = get(config, 'username', '')
    let dict.passwd = get(config, 'password', '')
    if adapter == 'mysql'
      if empty(dict.user)
        let dict.user = 'root'
      endif
      if dict.passwd == ''
        " Hack to override password from .my.cnf
        let dict.extra = ' --password='
      endif
    endif
    let dict.dbname = get(config, 'database', get(config, 'dbfile', ''))
    if len(dict.dbname) && dict.dbname !~ '^:' && adapter =~? '^sqlite'
      let dict.dbname = self.path(dict.dbname)
    endif
    let dict.profile = ''
    if adapter == 'ora'
      let dict.srvname = get(config, 'database', '')
    else
      let dict.srvname = get(config, 'host', '')
    endif
    let dict.host = get(config, 'host', '')
    let dict.port = get(config, 'port', '')
    let dict.dsnname = get(config, 'dsn', '')
    if dict.host =~? '^\cDBI:'
      if dict.host =~? '\c\<Trusted[_ ]Connection\s*=\s*yes\>'
        let dict.integratedlogin = 1
      endif
      let dict.host = matchstr(dict.host,'\c\<\%(Server\|Data Source\)\s*=\s*\zs[^;]*')
    endif
    call filter(dict,'len(v:val)')
    return dict
  endif
  return {}
endfunction

function! s:BufDatabase(level, ...)
  if exists("s:lock_database") || !exists('g:loaded_dbext') || !exists('b:rails_root')
    return
  endif
  let self = rails#app()
  if a:level > 1
    call self.cache.clear('db_config')
  elseif exists('g:rails_no_dbext')
    return
  endif
  if (a:0 && !empty(a:1))
    let env = a:1
  else
    let env = s:environment()
  endif
  if !self.cache.has('db_config') && a:level <= 0
    return
  endif
  let dict = self.dbext_settings(env)
  if empty(dict)
    return
  endif
  for key in ['type', 'profile', 'bin', 'user', 'passwd', 'dbname', 'srvname', 'host', 'port', 'dsnname', 'extra', 'integratedlogin']
    let b:dbext_{key} = get(dict,key,'')
  endfor
  if b:dbext_type == 'SQLITE'
    " dbext seems to have overlooked the release of sqlite3 a decade ago
    let g:dbext_default_SQLITE_bin = "sqlite3"
  endif
  if b:dbext_type == 'PGSQL'
    let $PGPASSWORD = b:dbext_passwd
  elseif exists('$PGPASSWORD')
    let $PGPASSWORD = ''
  endif
endfunction

call s:add_methods('app', ['db_config', 'db_url', 'dbext_settings'])

" }}}1
" Abbreviations {{{1

function! s:selectiveexpand(pat,good,default,...)
  if a:0 > 0
    let nd = a:1
  else
    let nd = ""
  endif
  let c = nr2char(getchar(0))
  let good = a:good
  if c == "" " ^]
    return s:sub(good.(a:0 ? " ".a:1 : ''),'\s+$','')
  elseif c == "\t"
    return good.(a:0 ? " ".a:1 : '')
  elseif c =~ a:pat
    return good.c.(a:0 ? a:1 : '')
  else
    return a:default.c
  endif
endfunction

function! s:AddSelectiveExpand(abbr,pat,expn,...)
  let expn  = s:gsub(s:gsub(a:expn        ,'[\"|]','\\&'),'\<','\\<Lt>')
  let expn2 = s:gsub(s:gsub(a:0 ? a:1 : '','[\"|]','\\&'),'\<','\\<Lt>')
  if a:0
    exe "inoreabbrev <buffer> <silent> ".a:abbr." <C-R>=<SID>selectiveexpand(".string(a:pat).",\"".expn."\",".string(a:abbr).",\"".expn2."\")<CR>"
  else
    exe "inoreabbrev <buffer> <silent> ".a:abbr." <C-R>=<SID>selectiveexpand(".string(a:pat).",\"".expn."\",".string(a:abbr).")<CR>"
  endif
endfunction

function! s:AddTabExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'..',a:expn)
endfunction

function! s:AddBracketExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'[[.]',a:expn)
endfunction

function! s:AddColonExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'[:.]',a:expn)
endfunction

function! s:AddParenExpand(abbr,expn,...)
  if a:0
    call s:AddSelectiveExpand(a:abbr,'(',a:expn,a:1)
  else
    call s:AddSelectiveExpand(a:abbr,'(',a:expn,'')
  endif
endfunction

if !exists('g:rails_no_abbreviations') && type(get(g:, 'rails_abbreviations', {})) == type(0)
  call s:error('Use rails_no_abbreviations not rails_abbreviations to disable abbreviations')
  let g:rails_no_abbreviations = 1
endif

function! s:BufAbbreviations()
  " Some of these were cherry picked from the TextMate snippets
  if !exists('g:rails_no_abbreviations')
    let buffer = rails#buffer()
    " Limit to the right filetypes.  But error on the liberal side
    if buffer.type_name('controller','view','helper','test-functional','test-integration')
      Rabbrev pa[ params
      Rabbrev rq[ request
      Rabbrev rs[ response
      Rabbrev se[ session
      Rabbrev hd[ headers
      Rabbrev coo[ cookies
      Rabbrev fl[ flash
      Rabbrev rr( render
      Rabbrev rf( render :file\ =>\ 
      Rabbrev rj( render :json\ =>\ 
      Rabbrev rp( render :partial\ =>\ 
      Rabbrev rt( render :text\ =>\ 
      Rabbrev rx( render :xml\ =>\ 
      " ))))))
    endif
    if buffer.type_name('view','helper')
      Rabbrev dotiw distance_of_time_in_words
      Rabbrev taiw  time_ago_in_words
    endif
    if buffer.type_name('controller')
      Rabbrev re(  redirect_to
      Rabbrev rst( respond_to
      " ))
    endif
    if buffer.type_name() ==# 'model' || buffer.type_name('model-record')
      Rabbrev bt(    belongs_to
      Rabbrev ho(    has_one
      Rabbrev hm(    has_many
      Rabbrev habtm( has_and_belongs_to_many
      Rabbrev co(    composed_of
      Rabbrev va(    validates_associated
      Rabbrev vb(    validates_acceptance_of
      Rabbrev vc(    validates_confirmation_of
      Rabbrev ve(    validates_exclusion_of
      Rabbrev vf(    validates_format_of
      Rabbrev vi(    validates_inclusion_of
      Rabbrev vl(    validates_length_of
      Rabbrev vn(    validates_numericality_of
      Rabbrev vp(    validates_presence_of
      Rabbrev vu(    validates_uniqueness_of
      " )))))))))))))))
    endif
    if buffer.type_name('db-migration','db-schema')
      Rabbrev mac(  add_column
      Rabbrev mrnc( rename_column
      Rabbrev mrc(  remove_column
      Rabbrev mct(  create_table
      Rabbrev mcht( change_table
      Rabbrev mrnt( rename_table
      Rabbrev mdt(  drop_table
      " )))))))
    endif
    if buffer.type_name('test')
      Rabbrev ase(  assert_equal
      Rabbrev asko( assert_kind_of
      Rabbrev asnn( assert_not_nil
      Rabbrev asr(  assert_raise
      Rabbrev asre( assert_response
      Rabbrev art(  assert_redirected_to
      " ))))))
    endif
    Rabbrev logd( logger.debug
    Rabbrev logi( logger.info
    Rabbrev logw( logger.warn
    Rabbrev loge( logger.error
    Rabbrev logf( logger.fatal
    Rabbrev AR::  ActiveRecord
    Rabbrev AV::  ActionView
    Rabbrev AC::  ActionController
    Rabbrev AD::  ActionDispatch
    Rabbrev AS::  ActiveSupport
    Rabbrev AM::  ActionMailer
    Rabbrev AO::  ActiveModel
    Rabbrev AJ::  ActiveJob
    " )))))
    for pairs in
          \ items(type(get(g:, 'rails_abbreviations', 0)) == type({}) ? g:rails_abbreviations : {})
      call call(function(s:sid.'Abbrev'), [0, pairs[0]] + s:split(pairs[1]))
    endfor
    for hash in reverse(rails#buffer().projected('abbreviations'))
      for pairs in items(hash)
        call call(function(s:sid.'Abbrev'), [0, pairs[0]] + s:split(pairs[1]))
      endfor
    endfor
  endif
endfunction

function! s:Abbrev(bang,...) abort
  if !exists("b:rails_abbreviations")
    let b:rails_abbreviations = {}
  endif
  if a:0 > 3 || (a:bang && (a:0 != 1))
    return s:error("Rabbrev: invalid arguments")
  endif
  if a:0 == 0
    for key in sort(keys(b:rails_abbreviations))
      echo key . join(b:rails_abbreviations[key],"\t")
    endfor
    return
  endif
  let lhs = a:1
  let root = s:sub(lhs,'%(::|\(|\[)$','')
  if a:bang
    if has_key(b:rails_abbreviations,root)
      call remove(b:rails_abbreviations,root)
    endif
    exe "iunabbrev <buffer> ".root
    return
  endif
  if a:0 > 3 || a:0 < 2
    return s:error("Rabbrev: invalid arguments")
  endif
  let rhs = a:2
  if has_key(b:rails_abbreviations,root)
    call remove(b:rails_abbreviations,root)
  endif
  if lhs =~ '($'
    let b:rails_abbreviations[root] = ["(", rhs . (a:0 > 2 ? "\t".a:3 : "")]
    if a:0 > 2
      call s:AddParenExpand(root,rhs,a:3)
    else
      call s:AddParenExpand(root,rhs)
    endif
    return
  endif
  if a:0 > 2
    return s:error("Rabbrev: invalid arguments")
  endif
  if lhs =~ ':$'
    call s:AddColonExpand(root,rhs)
  elseif lhs =~ '\[$'
    call s:AddBracketExpand(root,rhs)
  elseif lhs =~ '\w$'
    call s:AddTabExpand(lhs,rhs)
  else
    return s:error("Rabbrev: unimplemented")
  endif
  let b:rails_abbreviations[root] = [matchstr(lhs,'\W*$'),rhs]
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
    return bundler#project(self.path()).gems()
  else
    return {}
  endif
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

function! s:app_engines() dict abort
  if self.cache.needs('engines') || self.cache.get('engines')[1] isnot# self.gems()
    let gems = self.gems()
    let gempath = escape(join(values(gems),','), ' ')
    if empty(gempath)
      call self.cache.set('engines', [[], gems])
    else
      call self.cache.set('engines', [sort(map(finddir('app', gempath, -1), 'fnamemodify(v:val, ":h")')), gems])
    endif
  endif
  return self.cache.get('engines')[0]
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
    for [pattern, original] in items(a:src)
      let projection = extend(copy(original), extra)
      if !has_key(projection, 'prefix') && !has_key(projection, 'format')
        let a:dest[pattern] = s:extend_projection(get(a:dest, pattern, {}), projection)
      endif
    endfor
  endif
  return a:dest
endfunction

let s:default_projections = {
      \  "*.example.yml": {"alternate": "{}.yml"},
      \  "*.yml": {"alternate": ["{}.example.yml", "{}.yml"]},
      \  "*.yml.example": {"alternate": "{}.yml"},
      \  "Gemfile": {"alternate": "Gemfile.lock", "type": "lib"},
      \  "Gemfile.lock": {"alternate": "Gemfile"},
      \  "README": {"alternate": "config/database.yml"},
      \  "README.*": {"alternate": "config/database.yml"},
      \  "Rakefile": {"type": "task"},
      \  "app/channels/*_channel.rb": {
      \    "template": ["class {camelcase|capitalize|colons}Channel < ActionCable::Channel", "end"],
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
      \    "template": ["class {camelcase|capitalize|colons}Job < ActiveJob::Base", "end"],
      \    "type": "job"
      \  },
      \  "app/mailers/*.rb": {
      \    "affinity": "controller",
      \    "template": ["class {camelcase|capitalize|colons} < ActionMailer::Base", "end"],
      \    "type": "mailer"
      \  },
      \  "app/models/*.rb": {
      \    "affinity": "model",
      \    "template": ["class {camelcase|capitalize|colons}", "end"],
      \    "type": "model"
      \  },
      \  "app/serializers/*_serializer.rb": {
      \    "template": ["class {camelcase|capitalize|colons}Serializer < ActiveModel::Serializer", "end"],
      \    "type": "serializer"
      \  },
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
      \  "gems.rb": {"alternate": "gems.locked", "type": "lib"},
      \  "gems.locked": {"alternate": "gems.rb"},
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
      \        "require 'spec_helper'",
      \        "",
      \        "describe {camelcase|capitalize|colons} do",
      \        "end"
      \      ],
      \      "type": "functional test"
      \    },
      \    "spec/features/*_spec.rb": {
      \      "template": [
      \        "require 'spec_helper'",
      \        "",
      \        "describe \"{underscore|capitalize|blank}\" do",
      \        "end"
      \      ],
      \      "type": "integration test"
      \    },
      \    "spec/helpers/*_spec.rb": {
      \      "template": [
      \        "require 'spec_helper'",
      \        "",
      \        "describe {camelcase|capitalize|colons} do",
      \        "end"
      \      ],
      \      "type": "unit test"
      \    },
      \    "spec/integration/*_spec.rb": {
      \      "template": [
      \        "require 'spec_helper'",
      \        "",
      \        "describe \"{underscore|capitalize|blank}\" do",
      \        "end"
      \      ],
      \      "type": "integration test"
      \    },
      \    "spec/lib/*_spec.rb": {"alternate": "lib/{}.rb"},
      \    "spec/mailers/*_spec.rb": {
      \      "affinity": "controller",
      \      "template": [
      \        "require 'spec_helper'",
      \        "",
      \        "describe {camelcase|capitalize|colons} do",
      \        "end"
      \      ],
      \      "type": "functional test"
      \    },
      \    "spec/models/*_spec.rb": {
      \      "affinity": "model",
      \      "template": [
      \        "require 'spec_helper'",
      \        "",
      \        "describe {camelcase|capitalize|colons} do",
      \        "end"
      \      ],
      \      "type": "unit test"
      \    },
      \    "spec/rails_helper.rb": {"type": "integration test"},
      \    "spec/requests/*_spec.rb": {
      \      "template": [
      \        "require 'spec_helper'",
      \        "",
      \        "describe \"{underscore|capitalize|blank}\" do",
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
            call s:combine_projections(gem_projections, rails#json_parse(readfile(self.path(file))))
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
    if self.has_path('config/projections.json')
      try
        let projections = rails#json_parse(readfile(self.path('config/projections.json')))
        if type(projections) == type({})
          call self.cache.set('projections', projections)
        endif
      catch /^invalid JSON:/
      endtry
    endif
  endif

  call s:combine_projections(dict, self.cache.get('projections'))
  return dict
endfunction

call s:add_methods('app', ['gems', 'has_gem', 'engines', 'projections'])

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

function! s:expand_placeholder(placeholder, expansions) abort
  let transforms = split(a:placeholder[1:-2], '|')
  if has_key(a:expansions, get(transforms, 0, '}'))
    let value = a:expansions[remove(transforms, 0)]
  elseif has_key(a:expansions, 'match')
    let value = a:expansions.match
  else
    return "\001"
  endif
  for transform in transforms
    if !has_key(s:transformations, transform)
      return "\001"
    endif
    let value = s:transformations[transform](value, a:expansions)
  endfor
  return value
endfunction

function! s:expand_placeholders(string, placeholders)
  if type(a:string) ==# type({}) || type(a:string) == type([])
    return map(copy(a:string), 's:expand_placeholders(v:val, a:placeholders)')
  endif
  let ph = extend({'%': '%'}, a:placeholders)
  let value = substitute(a:string, '{[^{}]*}', '\=s:expand_placeholder(submatch(0), ph)', 'g')
  let value = substitute(value, '%\([^: ]\)', '\=get(ph, submatch(1), "\001")', 'g')
  return value =~# "\001" ? '' : value
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
            \ 's': root,
            \ 'S': rails#camelize(root),
            \ 'h': toupper(root[0]) . tr(rails#underscore(root), '_', ' ')[1:-1],
            \ 'p': rails#pluralize(root),
            \ 'i': rails#singularize(root),
            \ '%': '%'}, a:0 ? a:1 : {})
      if suffix =~# '\.js\>'
        let ph.S = s:gsub(ph.S, '::', '.')
      endif
      let mine += map(s:getlist(all[pattern], a:key), '[s:expand_placeholders(v:val, ph), v:val]')
    endif
  endfor
  return filter(mine, '!empty(v:val[0])')
endfunction

function! s:readable_projected(key, ...) dict abort
  return map(self.projected_with_raw(a:key, a:0 ? a:1 : {}), 'v:val[0]')
endfunction

call s:add_methods('readable', ['projected', 'projected_with_raw'])

function! s:Set(bang,...)
  call s:warn('Rset is obsolete and has no effect')
endfunction

" }}}1
" Detection {{{1

function! s:SetBasePath() abort
  let self = rails#buffer()
  if self.app().path() =~ '://'
    return
  endif
  let add_dot = self.getvar('&path') =~# '^\.\%(,\|$\)'
  let old_path = s:pathsplit(s:sub(self.getvar('&path'),'^\.%(,|$)',''))

  let path = ['lib', 'vendor']
  let path += get(g:, 'rails_path_additions', [])
  let path += get(g:, 'rails_path', [])
  let path += ['app/models/concerns', 'app/controllers/concerns', 'app/controllers', 'app/helpers', 'app/mailers', 'app/models', 'app/jobs']

  let true = get(v:, 'true', 1)
  for [key, projection] in items(self.app().projections())
    if get(projection, 'path', 0) is true || get(projection, 'autoload', 0) is true
          \ || get(projection, 'path', 0) is 1 || get(projection, 'autoload', 0) is 1
      let path += split(key, '*')[0]
    endif
  endfor
  let path += filter(self.projected('path'), 'type(v:val) == type("")')

  let path += ['app/*', 'app/views']
  if self.controller_name() != ''
    let path += ['app/views/'.self.controller_name(), 'app/views/application', 'public']
  endif
  if self.app().has('test')
    let path += ['test', 'test/unit', 'test/functional', 'test/integration', 'test/controllers', 'test/helpers', 'test/mailers', 'test/models', 'test/jobs']
  endif
  if self.app().has('spec')
    let path += ['spec', 'spec/controllers', 'spec/helpers', 'spec/mailers', 'spec/models', 'spec/views', 'spec/lib', 'spec/features', 'spec/requests', 'spec/integration', 'spec/jobs']
  endif
  if self.app().has('cucumber')
    let path += ['features']
  endif
  let path += ['vendor/plugins/*/lib', 'vendor/plugins/*/test', 'vendor/rails/*/lib', 'vendor/rails/*/test']
  call map(path, 'rails#app().path(v:val)')
  let engine_paths = map(copy(self.app().engines()), 'v:val . "/app/*"')
  call self.setvar('&path',(add_dot ? '.,' : '').s:pathjoin(s:uniq(path + [self.app().path()] + old_path + engine_paths)))
endfunction

function! rails#buffer_setup() abort
  if !exists('b:rails_root')
    return ''
  endif
  let self = rails#buffer()
  let b:rails_cached_file_type = self.calculate_file_type()
  call s:BufMappings()
  call s:BufCommands()
  if !empty(findfile('macros/rails.vim', escape(&runtimepath, ' ')))
    runtime! macros/rails.vim
  endif
  silent doautocmd User Rails
  call s:BufProjectionCommands()
  call s:BufAbbreviations()
  call s:SetBasePath()
  let rp = s:gsub(self.app().path(),'[ ,]','\\&')
  if stridx(&tags,rp.'/tags') == -1
    let &l:tags = rp . '/tags,' . rp . '/tmp/tags,' . &tags
  endif
  call self.setvar('&includeexpr','rails#includeexpr(v:fname)')
  call self.setvar('&suffixesadd', s:sub(self.getvar('&suffixesadd'),'^$','.rb'))
  let ft = self.getvar('&filetype')
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
  elseif ft =~# 'yaml\>' || fnamemodify(self.name(),':e') ==# 'yml'
    call self.setvar('&define',self.define_pattern())
  elseif ft =~# '^eruby\>'
    call self.setvar('&define',self.define_pattern())
    if exists("g:loaded_ragtag")
      call self.setvar('ragtag_stylesheet_link_tag', "<%= stylesheet_link_tag '\r' %>")
      call self.setvar('ragtag_javascript_include_tag', "<%= javascript_include_tag '\r' %>")
      call self.setvar('ragtag_doctype_index', 10)
    endif
  elseif ft =~# '^haml\>'
    call self.setvar('&define',self.define_pattern())
    if exists("g:loaded_ragtag")
      call self.setvar('ragtag_stylesheet_link_tag', "= stylesheet_link_tag '\r'")
      call self.setvar('ragtag_javascript_include_tag', "= javascript_include_tag '\r'")
      call self.setvar('ragtag_doctype_index', 10)
    endif
  elseif ft =~# 'html\>'
    call self.setvar('&define', '\<id=["'']\=')
  endif
  if ft =~# '^eruby\>' || ft =~# '^yaml\>'
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
  let b:current_compiler = 'rake'
  let &l:makeprg = self.app().rake_command('static')
  let &l:errorformat .= ',chdir '.escape(self.app().path(), ',')

  if exists(':Dispatch') == 2 && !exists('g:autoloaded_dispatch')
    runtime! autoload/dispatch.vim
  endif
  if exists('*dispatch#dir_opt')
    let dir = dispatch#dir_opt(self.app().path())
  endif

  let dispatch = self.projected('dispatch')
  if !empty(dispatch) && exists(dir)
    call self.setvar('dispatch', dir . dispatch[0])
  elseif self.name() =~# '^public'
    call self.setvar('dispatch', ':Preview')
  elseif self.type_name('spec', 'cucumber')
    call self.setvar('dispatch', ':Runner')
  elseif self.type_name('test') && !self.app().has('rails5')
    call self.setvar('dispatch', ':Runner')
  elseif self.name() =~# '^\%(app\|config\|db\|lib\|log\|README\|Rakefile\|test\|spec\|features\)'
    if !exists('dir')
      call self.setvar('dispatch', ':Rails')
    elseif self.app().has('rails5')
      call self.setvar('dispatch',
            \ dir .
            \ self.app().ruby_script_command('bin/rails') .
            \ ' `=rails#buffer(' . self['#'] . ').default_rake_task(v:lnum)`')
    else
      call self.setvar('dispatch',
            \ dir . '-compiler=rails ' .
            \ self.app().rake_command('static') .
            \ ' `=rails#buffer(' . self['#'] . ').default_rake_task(v:lnum)`')
    endif
  endif
endfunction

" }}}1
" Autocommands {{{1

augroup railsPluginAuto
  autocmd!
  autocmd User BufEnterRails call s:RefreshBuffer()
  autocmd User BufEnterRails call s:resetomnicomplete()
  autocmd User BufEnterRails call s:BufDatabase(-1)
  autocmd User dbextPreConnection call s:BufDatabase(1)
  autocmd BufWritePost */config/database.yml      call rails#cache_clear("db_config")
  autocmd BufWritePost */config/projections.json  call rails#cache_clear("projections")
  autocmd BufWritePost */test/test_helper.rb      call rails#cache_clear("user_assertions")
  autocmd BufWritePost */config/routes.rb         call rails#cache_clear("named_routes")
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
