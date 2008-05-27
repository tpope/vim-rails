" autoload/rails.vim
" Author:       Tim Pope <vimNOSPAM@tpope.info>

" Install this file as autoload/rails.vim.  This file is sourced manually by
" plugin/rails.vim.  It is in autoload directory to allow for future usage of
" Vim 7's autoload feature.

" ============================================================================

" Exit quickly when:
" - this plugin was already loaded (or disabled)
" - when 'compatible' is set
if &cp || exists("g:autoloaded_rails")
  finish
endif
let g:autoloaded_rails = '2.0'

let s:cpo_save = &cpo
set cpo&vim

" Utility Functions {{{1

function! s:sub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! s:string(str)
  if exists("*string")
    return string(a:str)
  else
    return "'" . s:gsub(a:str,"'","'.\"'\".'") . "'"
  endif
endfunction

function! s:compact(ary)
  return s:sub(s:sub(s:gsub(a:ary,'\n\n+','\n'),'\n$',''),'^\n','')
endfunction

function! s:scrub(collection,item)
  " Removes item from a newline separated collection
  let col = "\n" . a:collection
  let idx = stridx(col,"\n".a:item."\n")
  let cnt = 0
  while idx != -1 && cnt < 100
    let col = strpart(col,0,idx).strpart(col,idx+strlen(a:item)+1)
    let idx = stridx(col,"\n".a:item."\n")
    let cnt = cnt + 1
  endwhile
  return strpart(col,1)
endfunction

function! s:escarg(p)
  return s:gsub(a:p,'[ !%#]','\\&')
endfunction

function! s:esccmd(p)
  return s:gsub(a:p,'[!%#]','\\&')
endfunction

function! s:ra()
  " Rails root, escaped for use as single argument
  return s:escarg(RailsRoot())
endfunction

function! s:rc()
  " Rails root, escaped for use with a command (spaces not escaped)
  return s:esccmd(RailsRoot())
endfunction

function! s:escvar(r)
  let r = fnamemodify(a:r,':~')
  let r = s:gsub(r,'\W','\="_".char2nr(submatch(0))."_"')
  let r = s:gsub(r,'^\d','_&')
  return r
endfunction

function! s:rv()
  " Rails root, escaped to be a variable name
  return s:escvar(RailsRoot())
endfunction

function! s:rquote(str)
  " Imperfect but adequate for Ruby arguments
  if a:str =~ '^[A-Za-z0-9_/.:-]\+$'
    return a:str
  elseif &shell =~? 'cmd'
    return '"'.s:gsub(s:gsub(a:str,'\','\\'),'"','\\"').'"'
  else
    return "'".s:gsub(s:gsub(a:str,'\','\\'),"'","'\\\\''")."'"
  endif
endfunction

function! s:sname()
  return fnamemodify(s:file,':t:r')
endfunction

function! s:hasfile(file)
  return filereadable(RailsRoot().'/'.a:file)
endfunction

function! s:rubyexestr(cmd)
  if RailsRoot() =~ '://'
    return "ruby ".a:cmd
  else
    return "ruby -C ".s:rquote(RailsRoot())." ".a:cmd
  endif
endfunction

function! s:rubyexestrwithfork(cmd)
  if s:getopt("ruby_fork_port","ab") && executable("ruby_fork_client")
    return "ruby_fork_client -p ".s:getopt("ruby_fork_port","ab")." ".a:cmd
  else
    return s:rubyexestr(a:cmd)
  endif
endfunction

function! s:rubyexebg(cmd)
  let cmd = s:esccmd(s:rubyexestr(a:cmd))
  if has("gui_win32")
    if &shellcmdflag == "-c" && ($PATH . &shell) =~? 'cygwin'
      silent exe "!cygstart -d ".s:rquote(RailsRoot())." ruby ".a:cmd
    else
      exe "!start ".cmd
    endif
  elseif exists("$STY") && !has("gui_running") && s:getopt("gnu_screen","abg") && executable("screen")
    silent exe "!screen -ln -fn -t ".s:sub(s:sub(a:cmd,'\s.*',''),'^%(script|-rcommand)/','rails-').' '.cmd
  else
    exe "!".cmd
  endif
  return v:shell_error
endfunction

function! s:rubyexe(cmd,...)
  if a:0
    call s:rubyexebg(a:cmd)
  else
    exe "!".s:esccmd(s:rubyexestr(a:cmd))
  endif
  return v:shell_error
endfunction

function! s:rubyeval(ruby,...)
  if a:0 > 0
    let def = a:1
  else
    let def = ""
  endif
  if !executable("ruby")
    return def
  endif
  let cmd = s:rubyexestr('-e '.s:rquote('begin; require %{rubygems}; rescue LoadError; end; begin; require %{active_support}; rescue LoadError; end; '.a:ruby))
  "let g:rails_last_ruby_command = cmd
  " If the shell is messed up, this command could cause an error message
  silent! let results = system(cmd)
  "let g:rails_last_ruby_result = results
  if v:shell_error != 0 " results =~ '-e:\d' || results =~ 'ruby:.*(fatal)'
    return def
  else
    return results
  endif
endfunction

function! s:railseval(ruby,...)
  if a:0 > 0
    let def = a:1
  else
    let def = ""
  endif
  if !executable("ruby")
    return def
  endif
  let args = "-r./config/boot -r ".s:rquote(RailsRoot()."/config/environment")." -e ".s:rquote(a:ruby)
  let cmd = s:rubyexestrwithfork(args)
  " If the shell is messed up, this command could cause an error message
  silent! let results = system(cmd)
  if v:shell_error != 0 " results =~ '-e:\d' || results =~ 'ruby:.*(fatal)'
    return def
  else
    return results
  endif
endfunction

function! s:endof(lnum)
  if a:lnum == 0
    return 0
  endif
  if &ft == "yaml" || expand("%:e") == "yml"
    return -1
  endif
  let cline = getline(a:lnum)
  let spc = matchstr(cline,'^\s*')
  let endpat = '\<end\>'
  if matchstr(getline(a:lnum+1),'^'.spc) && !matchstr(getline(a:lnum+1),'^'.spc.endpat) && matchstr(cline,endpat)
    return a:lnum
  endif
  let endl = a:lnum
  while endl <= line('$')
    let endl = endl + 1
    if getline(endl) =~ '^'.spc.endpat
      return endl
    elseif getline(endl) =~ '^=begin\>'
      while getline(endl) !~ '^=end\>' && endl <= line('$')
        let endl = endl + 1
      endwhile
      let endl = endl + 1
    elseif getline(endl) !~ '^'.spc && getline(endl) !~ '^\s*\%(#.*\)\=$'
      return 0
    endif
  endwhile
  return 0
endfunction

function! s:lastmethodline(...)
  if a:0
    let line = a:1
  else
    let line = line(".")
  endif
  while line > 0 && getline(line) !~ &l:define
    let line = line - 1
  endwhile
  let lend = s:endof(line)
  if lend < 0 || lend >= (a:0 ? a:1 : line("."))
    return line
  else
    return 0
  endif
endfunction

function! s:lastmethod()
  let line = s:lastmethodline()
  if line
    return s:sub(matchstr(getline(line),'\%('.&define.'\)\zs\h\%(\k\|[:.]\)*[?!=]\='),':$','')
  else
    return ""
  endif
endfunction

function! s:lastrespondtoline(...)
  let mline = s:lastmethodline()
  if a:0
    let line = a:1
  else
    let line = line(".")
  endif
  while line > mline && getline(line) !~ '\C^\s*respond_to\s*\%(\<do\)\s*|\zs\h\k*\ze|'
    let line = line - 1
  endwhile
  let lend = s:endof(line)
  if lend >= (a:0 ? a:1 : line("."))
    return line
  else
    return -1
  endif
endfunction

function! s:lastformat()
  let rline = s:lastrespondtoline()
  if rline
    let variable = matchstr(getline(rline),'\C^\s*respond_to\s*\%(\<do\|{\)\s*|\zs\h\k*\ze|')
    let line = line('.')
    while line > rline
      let match = matchstr(getline(line),'\C^\s*'.variable.'\s*\.\s*\zs\h\k*')
      if match != ''
        return match
      endif
      let line = line - 1
    endwhile
  endif
  return ""
endfunction

function! s:format(...)
  if RailsFileType() =~ '^view\>'
    let format = fnamemodify(RailsFilePath(),':r:e')
  else
    let format = s:lastformat()
  endif
  if format == ''
    if fnamemodify(RailsFilePath(),':e') == 'rhtml'
      let format = 'html'
    elseif fnamemodify(RailsFilePath(),':e') == 'rxml'
      let format = 'xml'
    elseif fnamemodify(RailsFilePath(),':e') == 'rjs'
      let format = 'js'
    elseif a:0
      return a:1
    endif
  endif
  return format
endfunction

let s:view_types = 'rhtml,erb,rxml,builder,rjs,mab,liquid,haml,dryml,mn'

function! s:viewspattern()
  return '\%('.s:gsub(s:view_types,',','\\|').'\)'
endfunction

function! s:controller(...)
  let t = RailsFileType()
  let f = RailsFilePath()
  let o = s:getopt("controller","lb")
  if o != ""
    return o
  elseif f =~ '\<app/views/layouts/'
    return s:sub(f,'.*<app/views/layouts/(.{-})\..*','\1')
  elseif f =~ '\<app/views/'
    return s:sub(f,'.*<app/views/(.{-})/\k+\.\k+%(\.\k+)=$','\1')
  elseif f =~ '\<app/helpers/.*_helper\.rb$'
    return s:sub(f,'.*<app/helpers/(.{-})_helper\.rb$','\1')
  elseif f =~ '\<app/controllers/.*\.rb$'
    return s:sub(f,'.*<app/controllers/(.{-})%(_controller)=\.rb$','\1')
  elseif f =~ '\<app/apis/.*_api\.rb$'
    return s:sub(f,'.*<app/apis/(.{-})_api\.rb$','\1')
  elseif f =~ '\<test/functional/.*_test\.rb$'
    return s:sub(f,'.*<test/functional/(.{-})%(_controller)=_test\.rb$','\1')
  elseif f =~ '\<spec/controllers/.*_spec\.rb$'
    return s:sub(f,'.*<spec/controllers/(.{-})%(_controller)=_spec\.rb$','\1')
  elseif f =~ '\<spec/helpers/.*_helper_spec\.rb$'
    return s:sub(f,'.*<spec/helpers/(.{-})_helper_spec\.rb$','\1')
  elseif f =~ '\<spec/views/.*/\w\+_view_spec\.rb$'
    return s:sub(f,'.*<spec/views/(.{-})/\w+_view_spec\.rb$','\1')
  elseif f =~ '\<components/.*_controller\.rb$'
    return s:sub(f,'.*<components/(.{-})_controller\.rb$','\1')
  elseif f =~ '\<components/.*\.'.s:viewspattern().'$'
    return s:sub(f,'.*<components/(.{-})/\k+\.\k+$','\1')
  elseif f =~ '\<app/models/.*\.rb$' && t =~ '^model-mailer\>'
    return s:sub(f,'.*<app/models/(.{-})\.rb$','\1')
  elseif f =~ '\<public/stylesheets/.*\.css$'
    return s:sub(f,'.*<public/stylesheets/(.{-})\.css$','\1')
  elseif a:0 && a:1
    return s:pluralize(s:model())
  endif
  return ""
endfunction

function! s:model(...)
  let f = RailsFilePath()
  let o = s:getopt("model","lb")
  if o != ""
    return o
  elseif f =~ '\<app/models/.*_observer.rb$'
    return s:sub(f,'.*<app/models/(.*)_observer\.rb$','\1')
  elseif f =~ '\<app/models/.*\.rb$'
    return s:sub(f,'.*<app/models/(.*)\.rb$','\1')
  elseif f =~ '\<test/unit/.*_observer_test\.rb$'
    return s:sub(f,'.*<test/unit/(.*)_observer_test\.rb$','\1')
  elseif f =~ '\<test/unit/.*_test\.rb$'
    return s:sub(f,'.*<test/unit/(.*)_test\.rb$','\1')
  elseif f =~ '\<spec/models/.*_spec\.rb$'
    return s:sub(f,'.*<spec/models/(.*)_spec\.rb$','\1')
  elseif f =~ '\<\%(test\|spec\)/fixtures/.*\.\w*\~\=$'
    return s:singularize(s:sub(f,'.*<%(test|spec)/fixtures/(.*)\.\w*\~=$','\1'))
  elseif a:0 && a:1
    return s:singularize(s:controller())
  endif
  return ""
endfunction

function! s:underscore(str)
  let str = s:gsub(a:str,'::','/')
  let str = s:gsub(str,'(\u+)(\u\l)','\1_\2')
  let str = s:gsub(str,'(\l|\d)(\u)','\1_\2')
  let str = s:gsub(str,'-','_')
  let str = tolower(str)
  return str
endfunction

function! s:camelize(str)
  let str = s:gsub(a:str,'/(.)','::\u\1')
  let str = s:gsub(str,'%([_-]|<)(.)','\u\1')
  return str
endfunction

function! s:singularize(word)
  " Probably not worth it to be as comprehensive as Rails but we can
  " still hit the common cases.
  let word = a:word
  if word =~? '\.js$' || word == ''
    return word
  endif
  let word = s:sub(word,'eople$','ersons')
  let word = s:sub(word,'[aeio]@<!ies$','ys')
  let word = s:sub(word,'xe[ns]$','xs')
  let word = s:sub(word,'ves$','fs')
  let word = s:sub(word,'ss%(es)=$','sss')
  let word = s:sub(word,'s$','')
  return word
endfunction

function! s:pluralize(word)
  let word = a:word
  if word == ''
    return word
  endif
  let word = s:sub(word,'[aeio]@<!y$','ie')
  let word = s:sub(word,'%([osxz]|[cs]h)$','&e')
  let word = s:sub(word,'f@<!f$','ve')
  let word = word."s"
  let word = s:sub(word,'ersons$','eople')
  return word
endfunction

function! s:usesubversion()
  if !exists("b:rails_use_subversion")
    let b:rails_use_subversion = s:getopt("subversion","abg") && (RailsRoot()!="") && isdirectory(RailsRoot()."/.svn")
  endif
  return b:rails_use_subversion
endfunction

function! s:environment()
  if exists('$RAILS_ENV')
    return $RAILS_ENV
  else
    return "development"
  endif
endfunction

function! s:environments(...)
  let e = s:getopt("environment","abg")
  if e == ''
    return "development\ntest\nproduction"
  else
    return s:gsub(e,'[:;,- ]',"\n")
  endif
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
endfunction

function! s:debug(str)
  if g:rails_debug
    echohl Debug
    echomsg a:str
    echohl None
  endif
endfunction

" }}}1
" "Public" Interface {{{1

" RailsRoot() is the only official public function

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

function! RailsFilePath()
  if !exists("b:rails_root")
    return ""
  elseif exists("b:rails_file_path")
    return b:rails_file_path
  endif
  let f = s:gsub(expand('%:p'),'\\ @!','/')
  let f = s:sub(f,'/$','')
  if s:gsub(b:rails_root,'\\ @!','/') == strpart(f,0,strlen(b:rails_root))
    return strpart(f,strlen(b:rails_root)+1)
  else
    return f
  endif
endfunction

function! RailsFile()
  return RailsFilePath()
endfunction

function! RailsFileType()
  if !exists("b:rails_root")
    return ""
  elseif exists("b:rails_file_type")
    return b:rails_file_type
  elseif exists("b:rails_cached_file_type")
    return b:rails_cached_file_type
  endif
  let f = RailsFilePath()
  let e = fnamemodify(RailsFilePath(),':e')
  let r = ""
  let top = getline(1)." ".getline(2)." ".getline(3)." ".getline(4)." ".getline(5).getline(6)." ".getline(7)." ".getline(8)." ".getline(9)." ".getline(10)
  if f == ""
    let r = f
  elseif f =~ '_controller\.rb$' || f =~ '\<app/controllers/.*\.rb$'
    if top =~ '\<wsdl_service_name\>'
      let r = "controller-api"
    else
      let r = "controller"
    endif
  elseif f =~ '_api\.rb'
    let r = "api"
  elseif f =~ '\<test/test_helper\.rb$'
    let r = "test"
  elseif f =~ '\<spec/spec_helper\.rb$'
    let r = "spec"
  elseif f =~ '_helper\.rb$'
    let r = "helper"
  elseif f =~ '\<app/models\>'
    let class = matchstr(top,'\<Acti\w\w\u\w\+\%(::\h\w*\)\+\>')
    if class == "ActiveResoure::Base"
      let class = "ares"
      let r = "model-ares"
    elseif class != ''
      "let class = s:sub(class,'::Base$','')
      let class = tolower(s:gsub(class,'[^A-Z]',''))
      let r = "model-".s:sub(class,'^amb>','mailer')
    elseif f =~ '_mailer\.rb$'
      let r = "model-mailer"
    elseif top =~ '\<\%(validates_\w\+_of\|set_\%(table_name\|primary_key\)\|has_one\|has_many\|belongs_to\)\>'
      let r = "model-arb"
    else
      let r = "model"
    endif
  elseif f =~ '\<app/views/layouts\>.*\.'
    let r = "view-layout-" . e
  elseif f =~ '\<\%(app/views\|components\)/.*/_\k\+\.\k\+\%(\.\k\+\)\=$'
    let r = "view-partial-" . e
  elseif f =~ '\<app/views\>.*\.' || f =~ '\<components/.*/.*\.'.s:viewspattern().'$'
    let r = "view-" . e
  elseif f =~ '\<test/unit/.*_test\.rb$'
    let r = "test-unit"
  elseif f =~ '\<test/functional/.*_test\.rb$'
    let r = "test-functional"
  elseif f =~ '\<test/integration/.*_test\.rb$'
    let r = "test-integration"
  elseif f =~ '\<spec/\w*s/.*_spec\.rb$'
    let r = s:sub(f,'.*<spec/(\w*)s/.*','spec-\1')
  elseif f =~ '\<\%(test\|spec\)/fixtures\>'
    if e == "yml"
      let r = "fixtures-yaml"
    else
      let r = "fixtures" . (e == "" ? "" : "-" . e)
    endif
  elseif f =~ '\<test/.*_test\.rb'
    let r = "test"
  elseif f =~ '\<spec/.*_spec\.rb'
    let r = "spec"
  elseif f =~ '\<db/migrate\>' || f=~ '\<db/schema\.rb$'
    let r = "migration"
  elseif f =~ '\<vendor/plugins/.*/recipes/.*\.rb$' || f =~ '\.rake$' || f =~ '\<\%(Rake\|Cap\)file$' || f =~ '\<config/deploy\.rb$'
    let r = "task"
  elseif f =~ '\<log/.*\.log$'
    let r = "log"
  elseif e == "css" || e == "js" || e == "html"
    let r = e
  elseif f =~ '\<config/routes\>.*\.rb$'
    let r = "config-routes"
  elseif f =~ '\<config/'
    let r = "config"
  endif
  return r
endfunction

function! RailsType()
  return RailsFileType()
endfunction

function! RailsEval(ruby,...)
  if !exists("b:rails_root")
    return a:0 ? a:1 : ""
  elseif a:0
    return s:railseval(a:ruby,a:1)
  else
    return s:railseval(a:ruby)
  endif
endfunction

" }}}1
" Autocommand Functions {{{1

function! s:QuickFixCmdPre()
  if exists("b:rails_root")
    if strpart(getcwd(),0,strlen(RailsRoot())) != RailsRoot()
      let s:last_dir = getcwd()
      echo "lchdir ".s:ra()
      "exe "lchdir ".s:ra()
      lchdir `=RailsRoot()`
    endif
  endif
endfunction

function! s:QuickFixCmdPost()
  if exists("s:last_dir")
    "exe "lchdir ".s:escarg(s:last_dir)
    lchdir `=s:last_dir`
    unlet s:last_dir
  endif
endfunction

" }}}1
" Commands {{{1

function! s:prephelp()
  let fn = fnamemodify(s:file,':h:h').'/doc/'
  if filereadable(fn.'rails.txt')
    if !filereadable(fn.'tags') || getftime(fn.'tags') <= getftime(fn.'rails.txt')
      silent! helptags `=fn`
    endif
  endif
endfunction

function! RailsHelpCommand(...)
  call s:prephelp()
  let topic = a:0 ? a:1 : ""
  if topic == "" || topic == "-"
    return "help rails"
  elseif topic =~ '^g:'
    return "help ".topic
  elseif topic =~ '^-'
    return "help rails".topic
  else
    return "help rails-".topic
  endif
endfunction

function! s:BufCommands()
  call s:BufFinderCommands() " Provides Rcommand!
  call s:BufNavCommands()
  call s:BufScriptWrappers()
  Rcommand! -buffer -bar -nargs=? -bang -complete=custom,s:RakeComplete    Rake     :call s:Rake(<bang>0,<q-args>)
  Rcommand! -buffer -bar -nargs=? -bang -complete=custom,s:PreviewComplete Rpreview :call s:Preview(<bang>0,<q-args>)
  Rcommand! -buffer -bar -nargs=? -bang -complete=custom,s:environments    Rlog     :call s:Log(<bang>0,<q-args>)
  Rcommand! -buffer -bar -nargs=* -bang -complete=custom,s:SetComplete     Rset     :call s:Set(<bang>0,<f-args>)
  command! -buffer -bar -nargs=0 Rtags       :call s:Tags(<bang>0)
  " Embedding all this logic directly into the command makes the error
  " messages more concise.
  command! -buffer -bar -nargs=? -bang Rdoc  :
        \ if <bang>0 || <q-args> =~ "^\\([:'-]\\|g:\\)" |
        \   exe RailsHelpCommand(<q-args>) |
        \ else | call s:Doc(<bang>0,<q-args>) | endif
  command! -buffer -bar -nargs=0 -bang Rrefresh :if <bang>0|unlet! g:autoloaded_rails|source `=s:file`|endif|call s:Refresh(<bang>0)
  if exists(":Project")
    command! -buffer -bar -nargs=? -bang  Rproject :call s:Project(<bang>0,<q-args>)
  endif
  if exists("g:loaded_dbext")
    Rcommand! -buffer -bar -nargs=? -bang  -complete=custom,s:environments   Rdbext   :call s:BufDatabase(2,<q-args>,<bang>0)
  endif
  let ext = expand("%:e")
  if ext =~ s:viewspattern()
    " TODO: complete controller names with trailing slashes here
    Rcommand! -buffer -bar -nargs=? -range -complete=custom,s:controllerList Rextract :<line1>,<line2>call s:Extract(<bang>0,<f-args>)
    command! -buffer -bar -nargs=? -range Rpartial :call s:warn("Warning: :Rpartial has been deprecated in favor of :Rextract") | <line1>,<line2>Rextract<bang> <args>
  endif
  if RailsFilePath() =~ '\<db/migrate/.*\.rb$'
    command! -buffer -bar                 Rinvert  :call s:Invert(<bang>0)
  endif
endfunction

function! s:Doc(bang, string)
  if a:string != ""
    if exists("g:rails_search_url")
      let query = substitute(a:string,'[^A-Za-z0-9_.~-]','\="%".printf("%02X",char2nr(submatch(0)))','g')
      let url = printf(g:rails_search_url, query)
    else
      return s:error("specify a g:rails_search_url with %s for a query placeholder")
    endif
  elseif isdirectory(RailsRoot()."/doc/api/classes")
    let url = RailsRoot()."/doc/api/index.html"
  elseif s:getpidfor("0.0.0.0","8808") > 0
    let url = "http://localhost:8808"
  else
    let url = "http://api.rubyonrails.org"
  endif
  call s:initOpenURL()
  if exists(":OpenURL")
    exe "OpenURL ".s:escarg(url)
  else
    return s:error("No :OpenURL command found")
  endif
endfunction

function! s:Log(bang,arg)
  if a:arg == ""
    let lf = "log/".s:environment().".log"
  else
    let lf = "log/".a:arg.".log"
  endif
  let size = getfsize(RailsRoot()."/".lf)
  if size >= 1048576
    call s:warn("Log file is ".((size+512)/1024)."KB.  Consider :Rake log:clear")
  endif
  if a:bang
    exe "cgetfile ".lf
    clast
  else
    if exists(":Tail")
      " TODO: check if :Tail works with `=`
      exe "Tail ".s:ra().'/'.lf
    else
      "exe "pedit ".s:ra().'/'.lf
      pedit `=RailsRoot().'/'.lf`
    endif
  endif
endfunction

function! RailsNewApp(bang,...)
  if a:0 == 0
    if a:bang
      echo "rails.vim version ".g:autoloaded_rails
    else
      !rails
    endif
    return
  endif
  let dir = ""
  if a:1 !~ '^-'
    let dir = a:1
  elseif a:{a:0} =~ '[\/]'
    let dir = a:{a:0}
  else
    let dir = a:1
  endif
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:rquote(expand(a:{c}))
    let c = c + 1
  endwhile
  "let str = s:sub(str,'^ ','')
  let dir = expand(dir)
  if isdirectory(fnamemodify(dir,':h')."/.svn") && g:rails_subversion
    let append = " -c"
  else
    let append = ""
  endif
  if g:rails_default_database != "" && str !~ '-d \|--database='
    let append = append." -d ".g:rails_default_database
  endif
  if a:bang
    let append = append." --force"
  endif
  exe "!rails".append.str
  if filereadable(dir."/".g:rails_default_file)
    "exe "edit ".s:escarg(dir)."/".g:rails_default_file
    edit `=dir.'/'.g:rails_default_file`
  endif
endfunction

function! s:Tags(bang)
  if exists("g:Tlist_Ctags_Cmd")
    let cmd = g:Tlist_Ctags_Cmd
  elseif executable("exuberant-ctags")
    let cmd = "exuberant-ctags"
  elseif executable("ctags-exuberant")
    let cmd = "ctags-exuberant"
  elseif executable("ctags")
    let cmd = "ctags"
  elseif executable("ctags.exe")
    let cmd = "ctags.exe"
  else
    return s:error("ctags not found")
  endif
  exe "!".cmd." -R ".s:ra()
endfunction

function! s:Refresh(bang)
  " What else?
  if a:bang
    unlet! s:rails_helper_methods
  endif
  if exists("g:rubycomplete_rails") && g:rubycomplete_rails && has("ruby")
    silent! ruby ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
    silent! ruby Dependencies.clear if defined?(Dependencies)
    if a:bang
      silent! ruby ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
    endif
  endif
  call s:cacheclear()
  silent doautocmd User BufLeaveRails
  if a:bang && s:cacheworks()
    let s:cache = {}
  endif
  let i = 1
  let max = bufnr('$')
  while i <= max
    let rr = getbufvar(i,"rails_root")
    if rr != ""
      unlet! s:user_classes_{s:escvar(rr)}
      unlet! s:dbext_type_{s:escvar(rr)}
      call setbufvar(i,"rails_refresh",1)
    endif
    let i = i + 1
  endwhile
  silent doautocmd User BufEnterRails
endfunction

function! s:RefreshBuffer()
  if exists("b:rails_refresh") && b:rails_refresh
    let oldroot = b:rails_root
    unlet! b:rails_root b:rails_use_subversion
    let b:rails_refresh = 0
    call RailsBufInit(oldroot)
    unlet! b:rails_refresh
  endif
endfunction

" }}}1
" Rake {{{1

" Depends: s:rubyexestrwithfork, s:sub, s:lastmethodline, s:getopt, s;rquote, s:QuickFixCmdPre, ...

" Current directory
let s:efm='%D(in\ %f),'
" Failure and Error headers, start a multiline message
let s:efm=s:efm
      \.'%A\ %\\+%\\d%\\+)\ Failure:,'
      \.'%A\ %\\+%\\d%\\+)\ Error:,'
      \.'%+A'."'".'%.%#'."'".'\ FAILED,'
" Exclusions
let s:efm=s:efm
      \.'%C%.%#(eval)%.%#,'
      \.'%C-e:%.%#,'
      \.'%C%.%#/lib/gems/%\\d.%\\d/gems/%.%#,'
      \.'%C%.%#/lib/ruby/%\\d.%\\d/%.%#,'
      \.'%C%.%#/vendor/rails/%.%#,'
" Specific to template errors
let s:efm=s:efm
      \.'%C\ %\\+On\ line\ #%l\ of\ %f,'
      \.'%CActionView::TemplateError:\ compile\ error,'
" stack backtrace is in brackets. if multiple lines, it starts on a new line.
let s:efm=s:efm
      \.'%Ctest_%.%#(%.%#):%#,'
      \.'%C%.%#\ [%f:%l]:,'
      \.'%C\ \ \ \ [%f:%l:%.%#,'
      \.'%C\ \ \ \ %f:%l:%.%#,'
      \.'%C\ \ \ \ \ %f:%l:%.%#]:,'
      \.'%C\ \ \ \ \ %f:%l:%.%#,'
" Catch all
let s:efm=s:efm
      \.'%Z%f:%l:\ %#%m,'
      \.'%Z%f:%l:,'
      \.'%C%m,'
" Syntax errors in the test itself
let s:efm=s:efm
      \.'%.%#.rb:%\\d%\\+:in\ `load'."'".':\ %f:%l:\ syntax\ error\\\, %m,'
      \.'%.%#.rb:%\\d%\\+:in\ `load'."'".':\ %f:%l:\ %m,'
" And required files
let s:efm=s:efm
      \.'%.%#:in\ `require'."'".':in\ `require'."'".':\ %f:%l:\ syntax\ error\\\, %m,'
      \.'%.%#:in\ `require'."'".':in\ `require'."'".':\ %f:%l:\ %m,'
" Exclusions
let s:efm=s:efm
      \.'%-G%.%#/lib/gems/%\\d.%\\d/gems/%.%#,'
      \.'%-G%.%#/lib/ruby/%\\d.%\\d/%.%#,'
      \.'%-G%.%#/vendor/rails/%.%#,'
      \.'%-G%.%#%\\d%\\d:%\\d%\\d:%\\d%\\d%.%#,'
" Final catch all for one line errors
let s:efm=s:efm
      \.'%-G%\\s%#from\ %.%#,'
      \.'%f:%l:\ %#%m,'
" Drop everything else
let s:efm=s:efm
      \.'%-G%.%#'

let s:efm_backtrace='%D(in\ %f),'
      \.'%\\s%#from\ %f:%l:%m,'
      \.'%\\s#{RAILS_ROOT}/%f:%l:\ %#%m,'
      \.'%\\s%#[%f:%l:\ %#%m,'
      \.'%\\s%#%f:%l:\ %#%m'

function! s:makewithruby(arg,...)
  if &efm == s:efm
    if a:0 ? a:1 : 1
      setlocal efm=\%-E-e:%.%#,\%+E%f:%l:\ parse\ error,%W%f:%l:\ warning:\ %m,%E%f:%l:in\ %*[^:]:\ %m,%E%f:%l:\ %m,%-C%\tfrom\ %f:%l:in\ %.%#,%-Z%\tfrom\ %f:%l,%-Z%p^,%-G%.%#
    endif
  endif
  let old_make = &makeprg
  let &l:makeprg = s:rubyexestrwithfork(a:arg)
  make
  let &l:makeprg = old_make
endfunction

function! s:Rake(bang,arg)
  let oldefm = &efm
  if a:bang
    let &l:errorformat = s:efm_backtrace
  endif
  let t = RailsFileType()
  let arg = a:arg
  if &filetype == "ruby" && arg == '' && g:rails_modelines
    let lnum = s:lastmethodline()
    let str = getline(lnum)."\n".getline(lnum+1)."\n".getline(lnum+2)."\n"
    let pat = '\s\+\zs.\{-\}\ze\%(\n\|\s\s\|#{\@!\|$\)'
    let mat = matchstr(str,'#\s*rake'.pat)
    let mat = s:sub(mat,'\s+$','')
    if mat != ""
      let arg = mat
    endif
  endif
  if arg == ''
    let opt = s:getopt('task','bl')
    if opt != ''
      let arg = opt
    endif
  endif
  let withrubyargs = '-r ./config/boot -r '.s:rquote(RailsRoot().'/config/environment').' -e "puts \%((in \#{Dir.getwd}))" '
  if arg =~# '^\%(stats\|routes\|notes\|db:\%(charset\|collation\|version\)\)\%(:\|$\)'
    " So you can see the output even with an inadequate redirect
    call s:QuickFixCmdPre()
    exe "!".&makeprg." ".arg
    call s:QuickFixCmdPost()
  elseif arg =~ '^preview\>'
    exe 'R'.s:gsub(arg,':','/')
  elseif arg =~ '^runner:'
    let arg = s:sub(arg,'^runner:','')
    let root = matchstr(arg,'%\%(:\w\)*')
    let file = expand(root).matchstr(arg,'%\%(:\w\)*\zs.*')
    if file =~ '[@#].*$'
      let extra = " -- -n ".matchstr(file,'[@#]\zs.*')
      let file = s:sub(file,'[@#].*','')
    else
      let extra = ''
    endif
    if s:hasfile(file) || s:hasfile(file.'.rb')
      call s:makewithruby(withrubyargs.'-r"'.file.'"'.extra,file !~# '_\%(spec\|test\)\%(\.rb\)\=$')
    else
      call s:makewithruby(withrubyargs.'-e '.s:esccmd(s:rquote(arg)))
    endif
  elseif arg == 'run' || arg == 'runner'
    call s:makewithruby(withrubyargs.'-r"'.RailsFilePath().'"',RailsFilePath() !~# '_\%(spec\|test\)\%(\.rb\)\=$')
  elseif arg =~ '^run:'
    let arg = s:sub(arg,'^run:','')
    let arg = s:sub(arg,'^%:h',expand('%:h'))
    let arg = s:sub(arg,'^%(\%|$|[@#]@=)',expand('%'))
    let arg = s:sub(arg,'[@#](\w+)$',' -- -n\1')
    call s:makewithruby(withrubyargs.'-r'.arg,arg !~# '_\%(spec\|test\)\.rb$')
  elseif arg != ''
    exe 'make '.arg
  elseif t =~ '^task\>'
    let lnum = s:lastmethodline()
    let line = getline(lnum)
    " We can't grab the namespace so only run tasks at the start of the line
    if line =~ '^\%(task\|file\)\>'
      exe 'make '.s:lastmethod()
    else
      make
    endif
  elseif t =~ '^spec\>'
    if RailsFilePath() =~# '\<test/test_helper\.rb$'
      make spec SPEC_OPTS=
    else
      make spec SPEC="%:p" SPEC_OPTS=
    endif
  elseif t =~ '^test\>'
    let meth = s:lastmethod()
    if meth =~ '^test_'
      let call = " -n".meth.""
    else
      let call = ""
    endif
    if t =~ '^test-\%(unit\|functional\|integration\)$'
      exe "make ".s:sub(s:gsub(t,'-',':'),'unit$|functional$','&s')." TEST=\"%:p\"".s:sub(call,'^ ',' TESTOPTS=')
    elseif RailsFilePath() =~# '\<test/test_helper\.rb$'
      make test
    else
      call s:makewithruby('-e "puts \%((in \#{Dir.getwd}))" -r"%:p" -- '.call,0)
    endif
  elseif t=~ '^\%(db-\)\=migration\>' && RailsFilePath() !~# '\<db/schema\.rb$'
    let ver = matchstr(RailsFilePath(),'\<db/migrate/0*\zs\d*\ze_')
    if ver != ""
      exe "make db:migrate VERSION=".ver
    else
      make db:migrate
    endif
  elseif t=~ '^model\>'
    make test:units TEST="%:p:r:s?[\/]app[\/]models[\/]?/test/unit/?_test.rb"
  elseif t=~ '^api\>'
    make test:units TEST="%:p:r:s?[\/]app[\/]apis[\/]?/test/functional/?_test.rb"
  elseif t=~ '^\<\%(controller\|helper\|view\)\>'
    if RailsFilePath() =~ '\<app/' && s:controller() !~# '^\%(application\)\=$'
      exe 'make test:functionals TEST="'.s:ra().'/test/functional/'.s:controller().'_controller_test.rb"'
    else
      make test:functionals
    endif
  else
    make
  endif
  if oldefm != ''
    let &l:errorformat = oldefm
  endif
endfunction

function! s:RakeComplete(A,L,P)
  return g:rails_rake_tasks
endfunction

" }}}1
" Preview {{{1

" Depends: s:getopt, s:sub, s:controller, s:lastmethod
" Provides: s:initOpenURL

function! s:initOpenURL()
  if !exists(":OpenURL")
    if has("gui_mac") || has("gui_macvim") || exists("$SECURITYSESSIONID")
      command -bar -nargs=1 OpenURL :!open <args>
    elseif has("gui_win32")
      command -bar -nargs=1 OpenURL :!start cmd /cstart /b <args>
    elseif executable("sensible-browser")
      command -bar -nargs=1 OpenURL :!sensible-browser <args>
    endif
  endif
endfunction

" This returns the URI with a trailing newline if it is found
function! s:scanlineforuri(lnum)
  let line = getline(a:lnum)
  let url = matchstr(line,"\\v\\C%(%(GET|PUT|POST|DELETE)\\s+|\w+:/)/[^ \n\r\t<>\"]*[^] .,;\n\r\t<>\":]")
  if url =~ '\C^\u\+\s\+'
    let method = matchstr(url,'^\u\+')
    let url = matchstr(url,'\s\+\zs.*')
    if method !=? "GET"
      if url =~ '?'
        let url = url.'&'
      else
        let url = url.'?'
      endif
      let url = url.'_method='.tolower(method)
    endif
  endif
  if url != ""
    return s:sub(url,'^/','') . "\n"
  else
    return ""
  endif
endfunction

function! s:defaultpreview()
  let ret = ''
  if s:getopt('preview','l') != ''
    let uri = s:getopt('preview','l')
  elseif s:controller() != '' && s:controller() != 'application' && RailsFilePath() !~ '^public/'
    if RailsFileType() =~ '^controller\>'
      let start = s:lastmethodline() - 1
      if start + 1
        while getline(start) =~ '^\s*\%(#.*\)\=$'
          let ret = s:scanlineforuri(start).ret
          let start = start - 1
        endwhile
        let ret = ret.s:controller().'/'.s:lastmethod().'/'
      else
        let ret = ret.s:controller().'/'
      endif
    elseif s:getopt('preview','b') != ''
      let ret = s:getopt('preview','b')
    elseif RailsFileType() =~ '^view\%(-partial\|-layout\)\@!'
      let ret = ret.s:controller().'/'.expand('%:t:r:r').'/'
    endif
  elseif s:getopt('preview','b') != ''
    let uri = s:getopt('preview','b')
  elseif RailsFilePath() =~ '^public/'
    let ret = s:sub(RailsFilePath(),'^public/','')
  elseif s:getopt('preview','ag') != ''
    let ret = s:getopt('preview','ag')
  endif
  return ret
endfunction

function! s:Preview(bang,arg)
  let root = s:getopt("root_url")
  if root == ''
    let root = s:getopt("url")
  endif
  let root = s:sub(root,'/$','')
  if a:arg =~ '://'
    let uri = a:arg
  elseif a:arg != ''
    let uri = root.'/'.s:sub(a:arg,'^/','')
  else
    let uri = matchstr(s:defaultpreview(),'.\{-\}\%(\n\@=\|$\)')
    let uri = root.'/'.s:sub(s:sub(uri,'^/',''),'/$','')
  endif
  call s:initOpenURL()
  if exists(':OpenURL') && !a:bang
    exe 'OpenURL '.uri
  else
    " Work around bug where URLs ending in / get handled as FTP
    let url = uri.(uri =~ '/$' ? '?' : '')
    silent exe 'pedit '.url
    wincmd w
    if &filetype == ''
      if uri =~ '\.css$'
        setlocal filetype=css
      elseif uri =~ '\.js$'
        setlocal filetype=javascript
      elseif getline(1) =~ '^\s*<'
        setlocal filetype=xhtml
      endif
    endif
    call RailsBufInit(RailsRoot())
    map <buffer> <silent> q :bwipe<CR>
    wincmd p
    if !a:bang
      call s:warn("Define a :OpenURL command to use a browser")
    endif
  endif
endfunction

function! s:PreviewComplete(A,L,P)
  return s:defaultpreview()
endfunction

" }}}1
" Script Wrappers {{{1

" Depends: s:rquote, s:rubyexebg, s:rubyexe, s:rubyexestrwithfork, s:sub, s:getopt, s:usesubversion, s:user_classes_..., ..., s:pluginList, ...

function! s:BufScriptWrappers()
  Rcommand! -buffer -bar -nargs=+       -complete=custom,s:ScriptComplete   Rscript       :call s:Script(<bang>0,<f-args>)
  Rcommand! -buffer -bar -nargs=*       -complete=custom,s:ConsoleComplete  Rconsole      :call s:Console(<bang>0,'console',<f-args>)
  "Rcommand! -buffer -bar -nargs=*                                           Rbreakpointer :call s:Console(<bang>0,'breakpointer',<f-args>)
  Rcommand! -buffer -bar -nargs=*       -complete=custom,s:GenerateComplete Rgenerate     :call s:Generate(<bang>0,<f-args>)
  Rcommand! -buffer -bar -nargs=*       -complete=custom,s:DestroyComplete  Rdestroy      :call s:Destroy(<bang>0,<f-args>)
  Rcommand! -buffer -bar -nargs=? -bang -complete=custom,s:ServerComplete   Rserver       :call s:Server(<bang>0,<q-args>)
  Rcommand! -buffer -bang -nargs=1 -range=0 -complete=custom,s:RubyComplete Rrunner       :call s:Runner(<bang>0 ? -2 : (<count>==<line2>?<count>:-1),<f-args>)
  Rcommand! -buffer       -nargs=1 -range=0 -complete=custom,s:RubyComplete Rp            :call s:Runner(<count>==<line2>?<count>:-1,'p begin '.<f-args>.' end')
  Rcommand! -buffer       -nargs=1 -range=0 -complete=custom,s:RubyComplete Rpp           :call s:Runner(<count>==<line2>?<count>:-1,'require %{pp}; pp begin '.<f-args>.' end')
  Rcommand! -buffer       -nargs=1 -range=0 -complete=custom,s:RubyComplete Ry            :call s:Runner(<count>==<line2>?<count>:-1,'y begin '.<f-args>.' end')
endfunction

function! s:Script(bang,cmd,...)
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:rquote(a:{c})
    let c = c + 1
  endwhile
  if a:bang
    call s:rubyexebg(s:rquote("script/".a:cmd).str)
  else
    call s:rubyexe(s:rquote("script/".a:cmd).str)
  endif
endfunction

function! s:Runner(count,args)
  if a:count == -2
    call s:Script(a:bang,"runner",a:args)
  else
    let str = s:rubyexestrwithfork('-r./config/boot -e "require '."'commands/runner'".'" '.s:rquote(a:args))
    let res = s:sub(system(str),'\n$','')
    if a:count < 0
      echo res
    else
      exe a:count.'put =res'
    endif
  endif
endfunction

function! s:Console(bang,cmd,...)
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:rquote(a:{c})
    let c = c + 1
  endwhile
  call s:rubyexebg(s:rquote("script/".a:cmd).str)
endfunction

function! s:getpidfor(bind,port)
    if has("win32") || has("win64")
      let netstat = system("netstat -anop tcp")
      let pid = matchstr(netstat,'\<'.a:bind.':'.a:port.'\>.\{-\}LISTENING\s\+\zs\d\+')
    elseif executable('lsof')
      let pid = system("lsof -i 4tcp@".a:bind.':'.a:port."|grep LISTEN|awk '{print $2}'")
      let pid = s:sub(pid,'\n','')
    else
      let pid = ""
    endif
    return pid
endfunction

function! s:Server(bang,arg)
  let port = matchstr(a:arg,'\%(-p\|--port=\=\)\s*\zs\d\+')
  if port == ''
    let port = "3000"
  endif
  " TODO: Extract bind argument
  let bind = "0.0.0.0"
  if a:bang && executable("ruby")
    let pid = s:getpidfor(bind,port)
    if pid =~ '^\d\+$'
      echo "Killing server with pid ".pid
      if !has("win32")
        call system("ruby -e 'Process.kill(:TERM,".pid.")'")
        sleep 100m
      endif
      call system("ruby -e 'Process.kill(9,".pid.")'")
      sleep 100m
    endif
    if a:arg == "-"
      return
    endif
  endif
  if has("win32") || has("win64") || (exists("$STY") && !has("gui_running") && s:getopt("gnu_screen","abg") && executable("screen"))
    call s:rubyexebg(s:rquote("script/server")." ".a:arg)
  else
    "--daemon would be more descriptive but lighttpd does not support it
    call s:rubyexe(s:rquote("script/server")." ".a:arg." -d")
  endif
  call s:setopt('a:root_url','http://'.(bind=='0.0.0.0'?'localhost': bind).':'.port.'/')
endfunction

function! s:Destroy(bang,...)
  if a:0 == 0
    call s:rubyexe("script/destroy")
    return
  elseif a:0 == 1
    call s:rubyexe("script/destroy ".s:rquote(a:1))
    return
  endif
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:rquote(a:{c})
    let c = c + 1
  endwhile
  call s:rubyexe(s:rquote("script/destroy").str.(s:usesubversion()?' -c':''))
  unlet! s:user_classes_{s:rv()}
endfunction

function! s:Generate(bang,...)
  if a:0 == 0
    call s:rubyexe("script/generate")
    return
  elseif a:0 == 1
    call s:rubyexe("script/generate ".s:rquote(a:1))
    return
  endif
  let target = s:rquote(a:1)
  let str = ""
  let c = 2
  while c <= a:0
    let str = str . " " . s:rquote(a:{c})
    let c = c + 1
  endwhile
  if str !~ '-p\>' && str !~ '--pretend\>'
    let execstr = s:rubyexestr('-r./config/boot -e "require '."'commands/generate'".'" -- '.target." -p -f".str)
    let res = system(execstr)
    let file = matchstr(res,'\s\+\%(create\|force\)\s\+\zs\f\+\.rb\ze\n')
    if file == ""
      let file = matchstr(res,'\s\+\%(exists\)\s\+\zs\f\+\.rb\ze\n')
    endif
    "echo file
  else
    let file = ""
  endif
  if !s:rubyexe("script/generate ".target.(s:usesubversion()?' -c':'').str) && file != ""
    unlet! s:user_classes_{s:rv()}
    "exe "edit ".s:ra()."/".file
    edit `=RailsRoot().'/'.file`
  endif
endfunction

function! s:ScriptComplete(ArgLead,CmdLine,P)
  let cmd = s:sub(a:CmdLine,'^\u\w*\s+','')
  let P = a:P - strlen(a:CmdLine)+strlen(cmd)
  if cmd !~ '^[ A-Za-z0-9_=-]*$'
    " You're on your own, bud
    return ""
  elseif cmd =~ '^\w*$'
    return "about\nconsole\ndestroy\ngenerate\nperformance/benchmarker\nperformance/profiler\nplugin\nproccess/reaper\nprocess/spawner\nrunner\nserver"
  elseif cmd =~ '^\%(plugin\)\s\+'.a:ArgLead.'$'
    return "discover\nlist\ninstall\nupdate\nremove\nsource\nunsource\nsources"
  elseif cmd =~ '\%(plugin\)\s\+\%(install\|remove\)\s\+'.a:ArgLead.'$' || cmd =~ '\%(generate\|destroy\)\s\+plugin\s\+'.a:ArgLead.'$'
    return s:pluginList(a:ArgLead,a:CmdLine,a:P)
  elseif cmd =~ '^\%(generate\|destroy\)\s\+'.a:ArgLead.'$'
    return g:rails_generators
  elseif cmd =~ '^\%(generate\|destroy\)\s\+\w\+\s\+'.a:ArgLead.'$'
    let target = matchstr(cmd,'^\w\+\s\+\zs\w\+\ze\s\+')
    let pattern = "" " TODO
    if target =~# '^\%(\w*_\)\=controller$'
      return s:sub(s:controllerList(pattern,"",""),'^application\n=','')
    elseif target =~# '^\%(\w*_\)\=model$' || target =~# '^scaffold\%(_resource\)\=$' || target == 'mailer'
      return s:modelList(pattern,"","")
    elseif target == 'migration' || target == 'session_migration'
      return s:migrationList(pattern,"","")
    elseif target == 'integration_test'
      return s:integrationtestList(pattern,"","")
    elseif target == 'observer'
      " script/generate observer is in Edge Rails
      let observers = s:observerList(pattern,"","")
      let models = s:modelList(pattern,"","")
      if cmd =~ '^destroy\>'
        let models = ""
      endif
      while strlen(models) > 0
        let tmp = matchstr(models."\n",'.\{-\}\ze\n')
        let models = s:sub(models,'.{-}%(\n|$)','')
        if stridx("\n".observers."\n","\n".tmp."\n") == -1 && tmp !~'_observer$'
          let observers = observers."\n".tmp
        endif
      endwhile
      return s:sub(observers,'^\n','')
    elseif target == 'web_service'
      return s:apiList(pattern,"","")
    else
      return ""
    endif
  elseif cmd =~ '^\%(generate\|destroy\)\s\+scaffold\s\+\w\+\s\+'.a:ArgLead.'$'
    return s:sub(s:controllerList("","",""),'^application\n=','')
  elseif cmd =~ '^\%(console\)\s\+\(--\=\w\+\s\+\)\='.a:ArgLead."$"
    return s:environments()."\n-s\n--sandbox"
  elseif cmd =~ '^\%(server\)\s\+.*-e\s\+'.a:ArgLead."$"
    return s:environments()
  elseif cmd =~ '^\%(server\)\s\+'
    return "-p\n-b\n-e\n-m\n-d\n-u\n-c\n-h\n--port=\n--binding=\n--environment=\n--mime-types=\n--daemon\n--debugger\n--charset=\n--help\n"
  endif
  return ""
"  return s:relglob(RailsRoot()."/script/",a:ArgLead."*")
endfunction

function! s:CustomComplete(A,L,P,cmd)
  let L = "Rscript ".a:cmd." ".s:sub(a:L,'^\h\w*\s+','')
  let P = a:P - strlen(a:L) + strlen(L)
  return s:ScriptComplete(a:A,L,P)
endfunction

function! s:ServerComplete(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"server")
endfunction

function! s:ConsoleComplete(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"console")
endfunction

function! s:GenerateComplete(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"generate")
endfunction

function! s:DestroyComplete(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"destroy")
endfunction

function! s:RubyComplete(A,L,R)
  return s:gsub(RailsUserClasses(),' ','\n')."\nActiveRecord::Base"
endfunction

" }}}1
" Navigation {{{1

function! s:BufNavCommands()
  " TODO: completion
  "silent exe "command! -bar -buffer -nargs=? Rcd :cd ".s:ra()."/<args>"
  "silent exe "command! -bar -buffer -nargs=? Rlcd :lcd ".s:ra()."/<args>"
  command!   -buffer -bar -nargs=? Rcd   :cd `=RailsRoot().'/'.<q-args>`
  command!   -buffer -bar -nargs=? Rlcd :lcd `=RailsRoot().'/'.<q-args>`
  " Vim 6.2 chokes on script local completion functions (e.g., s:FindList).
  " :Rcommand! is a thin wrapper arround :command! which works around this
  Rcommand!   -buffer -bar -nargs=* -count=1 -complete=custom,s:FindList Rfind       :call s:Find(<bang>0,<count>,'' ,<f-args>)
  Rcommand!   -buffer -bar -nargs=* -count=1 -complete=custom,s:FindList REfind      :call s:Find(<bang>0,<count>,'E',<f-args>)
  Rcommand!   -buffer -bar -nargs=* -count=1 -complete=custom,s:FindList RSfind      :call s:Find(<bang>0,<count>,'S',<f-args>)
  Rcommand!   -buffer -bar -nargs=* -count=1 -complete=custom,s:FindList RVfind      :call s:Find(<bang>0,<count>,'V',<f-args>)
  Rcommand!   -buffer -bar -nargs=* -count=1 -complete=custom,s:FindList RTfind      :call s:Find(<bang>0,<count>,'T',<f-args>)
  Rcommand!   -buffer -bar -nargs=* -count=1 -complete=custom,s:FindList Rsfind      :<count>RSfind<bang> <args>
  Rcommand!   -buffer -bar -nargs=* -count=1 -complete=custom,s:FindList Rtabfind    :<count>RTfind<bang> <args>
  Rcommand!   -buffer -bar -nargs=* -bang    -complete=custom,s:EditList Redit       :call s:Edit(<bang>0,<count>,'' ,<f-args>)
  Rcommand!   -buffer -bar -nargs=* -bang    -complete=custom,s:EditList REedit      :call s:Edit(<bang>0,<count>,'E',<f-args>)
  Rcommand!   -buffer -bar -nargs=* -bang    -complete=custom,s:EditList RSedit      :call s:Edit(<bang>0,<count>,'S',<f-args>)
  Rcommand!   -buffer -bar -nargs=* -bang    -complete=custom,s:EditList RVedit      :call s:Edit(<bang>0,<count>,'V',<f-args>)
  Rcommand!   -buffer -bar -nargs=* -bang    -complete=custom,s:EditList RTedit      :call s:Edit(<bang>0,<count>,'T',<f-args>)
  command! -buffer -bar -nargs=0 A  :call s:Alternate(<bang>0,"")
  command! -buffer -bar -nargs=0 AE :call s:Alternate(<bang>0,"E")
  command! -buffer -bar -nargs=0 AS :call s:Alternate(<bang>0,"S")
  command! -buffer -bar -nargs=0 AV :call s:Alternate(<bang>0,"V")
  command! -buffer -bar -nargs=0 AT :call s:Alternate(<bang>0,"T")
  command! -buffer -bar -nargs=0 AN :call s:Related(<bang>0,"")
  command! -buffer -bar -nargs=0 R  :call s:Related(<bang>0,"")
  command! -buffer -bar -nargs=0 RE :call s:Related(<bang>0,"E")
  command! -buffer -bar -nargs=0 RS :call s:Related(<bang>0,"S")
  command! -buffer -bar -nargs=0 RV :call s:Related(<bang>0,"V")
  command! -buffer -bar -nargs=0 RT :call s:Related(<bang>0,"T")
  "command! -buffer -bar -nargs=0 RN :call s:Alternate(<bang>0,"")
endfunction

function! s:djump(def)
  let def = s:sub(a:def,'^[@#]','')
  if def != ''
    let ext = matchstr(def,'\.\zs.*')
    let def = matchstr(def,'[^.]*')
    let v:errmsg = ''
    silent! exe "djump ".def
    if ext != '' && (v:errmsg == '' || v:errmsg =~ '^E387')
      let rpat = '\C^\s*respond_to\s*\%(\<do\|{\)\s*|\zs\h\k*\ze|'
      let end = s:endof(line('.'))
      let rline = search(rpat,'',end)
      if rline > 0
        "call cursor(rline,1)
        let variable = matchstr(getline(rline),rpat)
        let success = search('\C^\s*'.variable.'\s*\.\s*\zs'.ext.'\>','',end)
        if !success
          silent! exe "djump ".def
        endif
      endif
    endif
  endif
endfunction

function! s:Find(bang,count,arg,...)
  let cmd = a:arg . (a:bang ? '!' : '')
  let str = ""
  if a:0
    let i = 1
    while i < a:0
      let str = str . s:escarg(a:{i}) . " "
      let i = i + 1
    endwhile
    let file = a:{i}
    let tail = matchstr(file,'[@#].*$')
    if tail != ""
      let file = s:sub(file,'[@#].*$','')
    endif
    if file != ""
      let file = s:RailsIncludefind(file)
    endif
  else
    let file = s:RailsFind()
    let tail = ""
  endif
  if file =~ '^\%(app\|config\|db\|public\|spec\|test\|vendor\)/.*\.' || !a:0 || 1
    call s:findedit((a:count==1?'' : a:count).cmd,file.tail,str)
  else
    " Old way
    let fcmd = (a:count==1?'' : a:count).s:findcmdfor(cmd)
    let fcmd = s:sub(fcmd,'(\d+)vert ','vert \1')
    if file != ""
      exe fcmd.' '.str.s:escarg(file)
    endif
    call s:djump(tail)
  endif
endfunction

function! s:Edit(bang,count,arg,...)
  let cmd = a:arg . (a:bang ? '!' : '')
  if a:0
    let str = ""
    let i = 1
    while i < a:0
      "let str = str . s:escarg(a:{i}) . " "
      let str = str . "`=a:".i."` "
      let i = i + 1
    endwhile
    let file = a:{i}
    call s:findedit(s:editcmdfor(cmd),file,str)
  else
    exe s:editcmdfor(cmd)
  endif
endfunction

function! s:FindList(ArgLead, CmdLine, CursorPos)
  if exists("*UserFileComplete") " genutils.vim
    return UserFileComplete(s:RailsIncludefind(a:ArgLead), a:CmdLine, a:CursorPos, 1, &path)
  else
    return ""
  endif
endfunction

function! s:EditList(ArgLead, CmdLine, CursorPos)
  return s:relglob("",a:ArgLead."*[^~]")
endfunction

function! RailsIncludeexpr()
  " Is this foolproof?
  if mode() =~ '[iR]' || expand("<cfile>") != v:fname
    return s:RailsIncludefind(v:fname)
  else
    return s:RailsIncludefind(v:fname,1)
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
  return s:findit('\s*:\%('.a:sym.'\)\s*=>\s*(\=\s*[@:'."'".'"]\(\f\+\)\>.\=',a:repl)
endfunction

function! s:findfromview(func,repl)
  return s:findit('\s*\%(<%\)\==\=\s*\<\%('.a:func.'\)\s*(\=\s*[@:'."'".'"]\(\f\+\)\>['."'".'"]\=\s*\%(%>\s*\)\=',a:repl)
endfunction

function! s:RailsFind()
  if filereadable(expand("<cfile>"))
    return expand("<cfile>")
  endif
  " UGH
  let format = s:format('html')
  let res = s:findit('\v\s*<require\s*\(=\s*File.dirname\(__FILE__\)\s*\+\s*[:'."'".'"](\f+)>.=',expand('%:h').'/\1')
  if res != ""|return res.(fnamemodify(res,':e') == '' ? '.rb' : '')|endif
  let res = s:findit('\v<File.dirname\(__FILE__\)\s*\+\s*[:'."'".'"](\f+)>['."'".'"]=',expand('%:h').'\1')
  if res != ""|return res|endif
  let res = s:findamethod('require','\1')
  if res != ""|return res.(fnamemodify(res,':e') == '' ? '.rb' : '')|endif
  let res = s:findamethod('belongs_to\|has_one\|composed_of\|validates_associated\|scaffold','app/models/\1.rb')
  if res != ""|return res|endif
  let res = s:singularize(s:findamethod('has_many\|has_and_belongs_to_many','app/models/\1'))
  if res != ""|return res.".rb"|endif
  let res = s:singularize(s:findamethod('create_table\|drop_table\|add_column\|rename_column\|remove_column\|add_index','app/models/\1'))
  if res != ""|return res.".rb"|endif
  let res = s:singularize(s:findasymbol('through','app/models/\1'))
  if res != ""|return res.".rb"|endif
  let res = s:findamethod('fixtures','fixtures/\1')
  if res != ""
    return RailsFilePath() =~ '\<spec/' ? 'spec/'.res : res
  endif
  let res = s:findamethod('map\.resources','app/controllers/\1_controller.rb')
  if res != ""|return res|endif
  let res = s:findamethod('layout','app/views/layouts/\1')
  if res != ""|return res|endif
  let res = s:findasymbol('layout','app/views/layouts/\1')
  if res != ""|return res|endif
  let res = s:findamethod('helper','app/helpers/\1_helper.rb')
  if res != ""|return res|endif
  let res = s:findasymbol('controller','app/controllers/\1_controller.rb')
  if res != ""|return res|endif
  let res = s:findasymbol('action','\1')
  if res != ""|return res|endif
  let res = s:sub(s:sub(s:findasymbol('partial','\1'),'^/',''),'\k+$','_&')
  if res != ""|return res."\n".s:findview(res)|endif
  let res = s:sub(s:sub(s:findfromview('render\s*(\=\s*:partial\s\+=>\s*','\1'),'^/',''),'\k+$','_&')
  if res != ""|return res."\n".s:findview(res)|endif
  let res = s:findamethod('render\s*:\%(template\|action\)\s\+=>\s*','\1.'.format.'\n\1')
  if res != ""|return res|endif
  let res = s:findamethod('redirect_to\s*(\=\s*:action\s\+=>\s*','\1')
  if res != ""|return res|endif
  let res = s:findfromview('stylesheet_link_tag','public/stylesheets/\1.css')
  if res != ""|return res|endif
  let res = s:sub(s:findfromview('javascript_include_tag','public/javascripts/\1.js'),'/defaults>','/application')
  if res != ""|return res|endif
  if RailsFileType() =~ '^controller\>'
    let res = s:findit('\s*\<def\s\+\(\k\+\)\>(\=',s:sub(s:sub(RailsFilePath(),'/controllers/','/views/'),'_controller\.rb$','').'/\1')
    if res != ""|return res|endif
  endif
  let isf_keep = &isfname
  set isfname=@,48-57,/,-,_,: ",\",'
  " TODO: grab visual selection in visual mode
  let cfile = expand("<cfile>")
  let res = s:RailsIncludefind(cfile,1)
  let &isfname = isf_keep
  return res
endfunction

function! s:initnamedroutes()
  if s:cacheneeds("named_routes")
    let exec = "ActionController::Routing::Routes.named_routes.each {|n,r| puts %{#{n} app/controllers/#{r.requirements[:controller]}_controller.rb##{r.requirements[:action]}}}"
    let string = s:railseval(exec)
    let routes = {}
    let list = split(string,"\n")
    let i = 0
    " If we use for, Vim 6.2 dumbly treats endfor like endfunction
    while i < len(list)
      let route = split(list[i]," ")
      let name = route[0]
      let routes[name] = route[1]
      let i = i + 1
    endwhile
    call s:cacheset("named_routes",routes)
  endif
endfunction

function! s:namedroutefile(route)
  call s:initnamedroutes()
  if s:cachehas("named_routes") && has_key(s:cache("named_routes"),a:route)
    return s:cache("named_routes")[a:route]
  endif
  return ""
endfunction

function! RailsNamedRoutes()
  call s:initnamedroutes()
  if s:cachehas("named_routes")
    return keys(s:cache("named_routes"))
  else
    " Dead code
    if s:cacheneeds("route_names")
      let lines = readfile(RailsRoot()."/config/routes.rb")
      let plurals = map(filter(copy(lines),'v:val =~# "^  map\\.resources\\s\\+:\\w"'),'matchstr(v:val,"^  map\\.resources\\=\\s\\+:\\zs\\w\\+")')
      let singulars = map(copy(plurals),'s:singularize(v:val)')
      let extras = map(copy(singulars),'"new_".v:val')+map(copy(singulars),'"edit_".v:val')
      let all = plurals + singulars + extras
      let named = map(filter(copy(lines),'v:val =~# "^  map\\.\\%(connect\\>\\|resources\\=\\>\\)\\@!\\w\\+"'),'matchstr(v:val,"^  map\\.\\zs\\w\\+")')
      call s:cacheset("route_names",named+all+map(copy(all),'"formatted_".v:val'))
    endif
    if s:cachehas("route_names")
      return s:cache("route_names")
    endif
  endif
endfunction

function! s:RailsIncludefind(str,...)
  if a:str == "ApplicationController"
    return "app/controllers/application.rb"
  elseif a:str == "Test::Unit::TestCase"
    return "test/unit/testcase.rb"
  elseif a:str == "<%="
    " Probably a silly idea
    return "action_view.rb"
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
  let str = s:sub(str,'^[:@]','')
  "let str = s:sub(str,"\\([\"']\\)\\(.*\\)\\1",'\2')
  let str = s:sub(str,':0x\x+$','') " For #<Object:0x...> style output
  let str = s:gsub(str,"[\"']",'')
  if line =~ '\<\(require\|load\)\s*(\s*$'
    return str
  endif
  let str = s:underscore(str)
  let fpat = '\(\s*\%("\f*"\|:\f*\|'."'\\f*'".'\)\s*,\s*\)*'
  if a:str =~ '\u'
    " Classes should always be in .rb files
    let str = str . '.rb'
  elseif line =~ ':partial\s*=>\s*'
    let str = s:sub(str,'([^/]+)$','_\1')
    let str = s:findview(str)
  elseif line =~ '\<layout\s*(\=\s*' || line =~ ':layout\s*=>\s*'
    let str = s:findview(s:sub(str,'^/=','layouts/'))
  elseif line =~ ':controller\s*=>\s*'
    let str = 'app/controllers/'.str.'_controller.rb'
  elseif line =~ '\<helper\s*(\=\s*'
    let str = 'app/helpers/'.str.'_helper.rb'
  elseif line =~ '\<fixtures\s*(\='.fpat
    if RailsFilePath() =~# '\<spec/'
      let str = s:sub(str,'^/@!','spec/fixtures/')
    else
      let str = s:sub(str,'^/@!','test/fixtures/')
    endif
  elseif line =~ '\<stylesheet_\(link_tag\|path\)\s*(\='.fpat
    let str = s:sub(str,'^/@!','/stylesheets/')
    let str = 'public'.s:sub(str,'^[^.]*$','&.css')
  elseif line =~ '\<javascript_\(include_tag\|path\)\s*(\='.fpat
    if str == "defaults"
      let str = "application"
    endif
    let str = s:sub(str,'^/@!','/javascripts/')
    let str = 'public'.s:sub(str,'^[^.]*$','&.js')
  elseif line =~ '\<\(has_one\|belongs_to\)\s*(\=\s*'
    let str = 'app/models/'.str.'.rb'
  elseif line =~ '\<has_\(and_belongs_to_\)\=many\s*(\=\s*'
    let str = 'app/models/'.s:singularize(str).'.rb'
  elseif line =~ '\<def\s\+' && expand("%:t") =~ '_controller\.rb'
    let str = s:sub(s:sub(RailsFilePath(),'/controllers/','/views/'),'_controller\.rb$','/'.str)
    "let str = s:sub(expand("%:p"),'.*[\/]app[\/]controllers[\/](.{-})_controller.rb','views/\1').'/'.str
    " FIXME: support nested extensions
    let vt = s:view_types.","
    while vt != ""
      let t = matchstr(vt,'[^,]*')
      let vt = s:sub(vt,'[^,]*,','')
      if filereadable(str.".".t)
        let str = str.".".t
        break
      endif
    endwhile
  elseif str =~ '_\%(path\|url\)$'
    " REST helpers
    let str = s:sub(str,'_%(path|url)$','')
    let str = s:sub(str,'^hash_for_','')
    let file = s:namedroutefile(str)
    if file == ""
      let str = s:sub(str,'^formatted_','')
      if str =~ '^\%(new\|edit\)_'
        let str = 'app/controllers/'.s:sub(s:pluralize(str),'^(new|edit)_(.*)','\2_controller.rb#\1')
      elseif str == s:singularize(str)
        " If the word can't be singularized, it's probably a link to the show
        " method.  We should verify by checking for an argument, but that's
        " difficult the way things here are currently structured.
        let str = 'app/controllers/'.s:pluralize(str).'_controller.rb#show'
      else
        let str = 'app/controllers/'.str.'_controller.rb#index'
      endif
    else
      let str = file
    endif
  elseif str !~ '/'
    " If we made it this far, we'll risk making it singular.
    let str = s:singularize(str)
    let str = s:sub(str,'_id$','')
  endif
  if str =~ '^/' && !filereadable(str)
    let str = s:sub(str,'^/','')
  endif
  if str =~ '^lib/' && !filereadable(str)
    let str = s:sub(str,'^lib/','')
  endif
  return str
endfunction

" }}}1
" File Finders {{{1

function! s:addfilecmds(type)
  let l = s:sub(a:type,'^.','\l&')
  let cmds = 'ESVT '
  let cmd = ''
  while cmds != ''
    let cplt = " -complete=custom,".s:sid.l."List"
    exe "command! -buffer -bar -nargs=*".cplt." R".cmd.l." :call s:".l.'Edit(<bang>0,"'.cmd.'",<f-args>)'
    let cmd = strpart(cmds,0,1)
    let cmds = strpart(cmds,1)
  endwhile
endfunction

function! s:BufFinderCommands()
  command! -buffer -bar -bang -nargs=+ Rcommand :call s:Command(<bang>0,<f-args>)
  call s:addfilecmds("model")
  call s:addfilecmds("view")
  call s:addfilecmds("controller")
  call s:addfilecmds("migration")
  call s:addfilecmds("observer")
  call s:addfilecmds("helper")
  call s:addfilecmds("api")
  call s:addfilecmds("layout")
  call s:addfilecmds("fixtures")
  call s:addfilecmds("unittest")
  call s:addfilecmds("functionaltest")
  call s:addfilecmds("integrationtest")
  call s:addfilecmds("stylesheet")
  call s:addfilecmds("javascript")
  call s:addfilecmds("task")
  call s:addfilecmds("lib")
  call s:addfilecmds("plugin")
endfunction

function! s:autocamelize(files,test)
  if a:test =~# '^\u'
    return s:camelize(a:files)
  else
    return a:files
  endif
endfunction

function! RailsUserClasses()
  if !exists("b:rails_root")
    return ""
  elseif s:getopt('classes','ab') != ''
    return s:getopt('classes','ab')
  endif
  let var = "user_classes_".s:rv()
  if !exists("s:".var)
    let s:{var} = s:sub(s:sub(s:gsub(s:camelize(
        \ s:relglob("app/models/","**/*",".rb") . "\n" .
        \ s:sub(s:relglob("app/controllers/","**/*",".rb"),'<application>','&_controller') . "\n" .
        \ s:relglob("app/helpers/","**/*",".rb") . "\n" .
        \ s:relglob("lib/","**/*",".rb") . "\n" .
        \ ""),'\n+',' '),'^\s+',''),'\s+$','')
  endif
  return s:{var}
endfunction

function! s:relglob(path,glob,...)
  " How could such a simple operation be so complicated?
  if exists("+shellslash") && ! &shellslash
    let old_ss = &shellslash
    let &shellslash = 1
  endif
  if a:path =~ '[\/]$'
    let path = a:path
  else
    let path = a:path . ''
  endif
  if path !~ '^/' && path !~ '^\w:' && RailsRoot() != ''
    let path = RailsRoot() . '/' . path
  endif
  let suffix = a:0 ? a:1 : ''
  let badres = glob(path.a:glob.suffix)."\n"
  if v:version <= 602
    " Nasty Vim bug in version 6.2
    let badres = glob(path.a:glob.suffix)."\n"
  endif
  let goodres = ""
  let striplen = strlen(path)
  let stripend = strlen(suffix)
  while strlen(badres) > 0
    let idx = stridx(badres,"\n")
    "if idx == -1
      "let idx = strlen(badres)
    "endif
    let tmp = strpart(badres,0,idx)
    let badres = strpart(badres,idx+1)
    let goodres = goodres.strpart(tmp,striplen,strlen(tmp)-striplen-stripend)
    if suffix == '' && isdirectory(tmp) && goodres !~ '/$'
      let goodres = goodres."/"
    endif
    let goodres = goodres."\n"
  endwhile
  "let goodres = s:gsub("\n".goodres,'\n.{-}\~\n','\n')
  if exists("old_ss")
    let &shellslash = old_ss
  endif
  return s:compact(goodres)
endfunction

if v:version <= 602
  " Yet another  Vim 6.2 limitation
  let s:recurse = "*"
else
  let s:recurse = "**/*"
endif

function! s:helperList(A,L,P)
  return s:autocamelize(s:relglob("app/helpers/",s:recurse,"_helper.rb"),a:A)
endfunction

function! s:controllerList(A,L,P)
  let con = s:gsub(s:relglob("app/controllers/",s:recurse,".rb"),'_controller>','')
  return s:autocamelize(con,a:A)
endfunction

function! s:viewList(A,L,P)
  let c = s:controller(1)
  let top = s:relglob("app/views/",a:A."*[^~]")
  if c != ''
    let local = s:relglob("app/views/".c."/",a:A."*.*[^~]")
    if local != ''
      return local."\n".top
    endif
  endif
  return top
endfunction

function! s:layoutList(A,L,P)
  return s:relglob("app/views/layouts/","*")
endfunction

function! s:stylesheetList(A,L,P)
  return s:relglob("public/stylesheets/",s:recurse,".css")
endfunction

function! s:javascriptList(A,L,P)
  return s:relglob("public/javascripts/",s:recurse,".js")
endfunction

function! s:modelList(A,L,P)
  let models = s:relglob("app/models/",s:recurse,".rb")."\n"
  " . matches everything, and no good way to exclude newline.  Lame.
  let models = s:gsub(models,'[ -~]*_observer\n',"")
  let models = s:compact(models)
  return s:autocamelize(models,a:A)
endfunction

function! s:observerList(A,L,P)
  return s:autocamelize(s:relglob("app/models/",s:recurse,"_observer.rb"),a:A)
endfunction

function! s:fixturesList(A,L,P)
  return s:compact(s:relglob("test/fixtures/",s:recurse)."\n".s:relglob("spec/fixtures/",s:recurse))
endfunction

function! s:migrationList(A,L,P)
  if a:A =~ '^\d'
    let migrations = s:relglob("db/migrate/",a:A."[0-9_]*",".rb")
    let migrations = s:gsub(migrations,'_.{-}($|\n)','\1')
    return migrations
  else
    let migrations = s:relglob("db/migrate/","[0-9]*[0-9]_".a:A."*",".rb")
    let migrations = s:gsub(migrations,'(^|\n)\d+_','\1')
    return s:autocamelize(migrations,a:A)
  endif
endfunction

function! s:apiList(A,L,P)
  return s:autocamelize(s:relglob("app/apis/",s:recurse,"_api.rb"),a:A)
endfunction

function! s:unittestList(A,L,P)
  return s:autocamelize(s:relglob("test/unit/",s:recurse,"_test.rb"),a:A)
endfunction

function! s:functionaltestList(A,L,P)
  return s:autocamelize(s:relglob("test/functional/",s:recurse,"_test.rb"),a:A)
endfunction

function! s:integrationtestList(A,L,P)
  return s:autocamelize(s:relglob("test/integration/",s:recurse,"_test.rb"),a:A)
endfunction

function! s:pluginList(A,L,P)
  if a:A =~ '/'
    return s:relglob('vendor/plugins/',matchstr(a:A,'.\{-\}/').'**/*')
  else
    return s:relglob('vendor/plugins/',"*","/init.rb")
  endif
endfunction

" Task files, not actual rake tasks
function! s:taskList(A,L,P)
  let top = s:relglob("lib/tasks/",s:recurse,".rake")
  if RailsFilePath() =~ '\<vendor/plugins/.'
    let path = s:sub(RailsFilePath(),'<vendor/plugins/[^/]*/\zs.*','tasks/')
    return s:relglob(path,s:recurse,".rake") . "\n" . top
  else
    return top
  endif
endfunction

function! s:libList(A,L,P)
  let all = s:relglob('lib/',s:recurse,".rb")
  if RailsFilePath() =~ '\<vendor/plugins/.'
    let path = s:sub(RailsFilePath(),'<vendor/plugins/[^/]*/\zs.*','lib/')
    let all = s:relglob(path,s:recurse,".rb") . "\n" . all
  endif
  return s:autocamelize(all,a:A)
endfunction

function! s:Command(bang,...)
  if a:bang
    let str = ""
    let i = 0
    while i < a:0
      let i = i + 1
      if a:{i} =~# '^-complete=custom,s:' && v:version <= 602
        let str = str . " " . s:sub(a:{i},',s:',','.s:sid)
      else
        let str = str . " " . a:{i}
      endif
    endwhile
    exe "command!".str
    return
  endif
  let suffix = ".rb"
  let filter = "**/*"
  let prefix = ""
  let default = ""
  let name = ""
  let i = 0
  while i < a:0
    let i = i + 1
    let arg = a:{i}
    if arg =~# '^-suffix='
      let suffix = matchstr(arg,'-suffix=\zs.*')
    elseif arg =~# '^-default='
      let default = matchstr(arg,'-default=\zs.*')
    elseif arg =~# '^-\%(glob\|filter\)='
      let filter = matchstr(arg,'-\w*=\zs.*')
    elseif arg !~# '^-'
      " A literal '\n'.  For evaluation below
      if name == ""
        let name = arg
      else
        let prefix = prefix."\\n".s:sub(arg,'/=$','/')
      endif
    endif
  endwhile
  let prefix = s:sub(prefix,'^\\n','')
  if name !~ '^[A-Za-z]\+$'
    return s:error("E182: Invalid command name")
  endif
  let cmds = 'ESVT '
  let cmd = ''
  while cmds != ''
    exe 'command! -buffer -bar -bang -nargs=* -complete=custom,'.s:sid.'CommandList R'.cmd.name." :call s:CommandEdit(<bang>0,'".cmd."','".name."',\"".prefix."\",".s:string(suffix).",".s:string(filter).",".s:string(default).",<f-args>)"
    let cmd = strpart(cmds,0,1)
    let cmds = strpart(cmds,1)
  endwhile
endfunction

function! s:CommandList(A,L,P)
  let cmd = matchstr(a:L,'\CR[A-Z]\=\w\+')
  exe cmd." &"
  let lp = s:last_prefix . "\n"
  let res = ""
  while lp != ""
    let p = matchstr(lp,'.\{-\}\ze\n')
    let lp = s:sub(lp,'.{-}\n','')
    let res = res . s:relglob(p,s:last_filter,s:last_suffix)."\n"
  endwhile
  let res = s:compact(res)
  if s:last_camelize
    return s:autocamelize(res,a:A)
  else
    return res
  endif
endfunction

function! s:CommandEdit(bang,cmd,name,prefix,suffix,filter,default,...)
  if a:0 && a:1 == "&"
    let s:last_prefix = a:prefix
    let s:last_suffix = a:suffix
    let s:last_filter = a:filter
    let s:last_camelize = (a:suffix =~# '\.rb$')
  else
    if a:default == "both()"
      if s:model() != ""
        let default = s:model()
      else
        let default = s:controller()
      endif
    elseif a:default == "model()"
      let default = s:model(1)
    elseif a:default == "controller()"
      let default = s:controller(1)
    else
      let default = a:default
    endif
    call s:EditSimpleRb(a:bang,a:cmd,a:name,a:0 ? a:1 : default,a:prefix,a:suffix)
  endif
endfunction

function! s:EditSimpleRb(bang,cmd,name,target,prefix,suffix)
  let cmd = s:findcmdfor(a:cmd.(a:bang?'!':''))
  if a:target == ""
    " Good idea to emulate error numbers like this?
    return s:error("E471: Argument required") " : R',a:name)
  "else
    "let g:target = a:target
  endif
  let f = s:underscore(a:target)
  let jump = matchstr(f,'[@#].*')
  let f = s:sub(f,'[@#].*','')
  if f == '.'
    let f = s:sub(f,'\.$','')
  else
    let f = f.a:suffix.jump
    if a:suffix !~ '\.'
      "let f = f.".rb"
    endif
  endif
  let f = s:gsub(a:prefix,'\n',f.'\n').f
  return s:findedit(cmd,f)
endfunction

function! s:migrationfor(file)
  let tryagain = 0
  let arg = a:file
  if arg =~ '^\d$'
    let glob = '00'.arg.'_*.rb'
  elseif arg =~ '^\d\d$'
    let glob = '0'.arg.'_*.rb'
  elseif arg =~ '^\d\d\d$'
    let glob = ''.arg.'_*.rb'
  elseif arg == ''
    if s:model(1) != ''
      let glob = '*_'.s:pluralize(s:model(1)).'.rb'
      let tryagain = 1
    else
      let glob = '*.rb'
    endif
  else
    let glob = '*'.arg.'*rb'
  endif
  let migr = s:sub(glob(RailsRoot().'/db/migrate/'.glob),'.*\n','')
  if migr == '' && tryagain
    let migr = s:sub(glob(RailsRoot().'/db/migrate/*.rb'),'.*\n','')
  endif
  if strpart(migr,0,strlen(RailsRoot())) == RailsRoot()
    let migr = strpart(migr,1+strlen(RailsRoot()))
  endif
  return migr
endfunction

function! s:migrationEdit(bang,cmd,...)
  let cmd = s:findcmdfor(a:cmd.(a:bang?'!':''))
  let arg = a:0 ? a:1 : ''
  let migr = arg == "." ? "db/migrate" : s:migrationfor(arg)
  if migr != ''
    call s:findedit(cmd,migr)
  else
    return s:error("Migration not found".(arg=='' ? '' : ': '.arg))
  endif
endfunction

function! s:fixturesEdit(bang,cmd,...)
  if a:0
    let c = s:underscore(a:1)
  else
    let c = s:pluralize(s:model(1))
  endif
  if c == ""
    return s:error("E471: Argument required")
  endif
  let e = fnamemodify(c,':e')
  let e = e == '' ? e : '.'.e
  let c = fnamemodify(c,':r')
  let file = 'test/fixtures/'.c.e
  if file =~ '\.\w\+$' && !s:hasfile("spec/fixtures/".c.e)
    call s:edit(a:cmd.(a:bang?'!':''),file)
  else
    call s:findedit(a:cmd.(a:bang?'!':''),file."\nspec/fixtures/".c.e)
  endif
endfunction

function! s:modelEdit(bang,cmd,...)
  call s:EditSimpleRb(a:bang,a:cmd,"model",a:0? a:1 : s:model(1),"app/models/",".rb")
endfunction

function! s:observerEdit(bang,cmd,...)
  call s:EditSimpleRb(a:bang,a:cmd,"observer",a:0? a:1 : s:model(1),"app/models/","_observer.rb")
endfunction

function! s:viewEdit(bang,cmd,...)
  if a:0
    let view = a:1
  elseif RailsFileType() == 'controller'
    let view = s:lastmethod()
  else
    let view = ''
  endif
  if view == ''
    return s:error("No view name given")
  elseif view == '.'
    return s:edit(a:cmd.(a:bang?'!':''),'app/views')
  elseif view !~ '/' && s:controller(1) != ''
    let view = s:controller(1) . '/' . view
  endif
  if view !~ '/'
    return s:error("Cannot find view without controller")
  endif
  let file = "app/views/".view
  let found = s:findview(view)
  if found != ''
    call s:edit(a:cmd.(a:bang?'!':''),found)
  elseif file =~ '\.\w\+\.\w\+$' || file =~ '\.'.s:viewspattern().'$'
    call s:edit(a:cmd.(a:bang?'!':''),file)
  elseif file =~ '\.\w\+$'
    call s:findedit(a:cmd.(a:bang?'!':''),file)
  else
    let format = s:format('html')
    if glob(RailsRoot().'/'.file.'.'.format.'.*[^~]') != ''
      let file = file . '.' . format
    endif
    call s:findedit(a:cmd.(a:bang?'!':''),file)
  endif
endfunction

function! s:findview(name)
  " TODO: full support of nested extensions
  let c = a:name
  let pre = "app/views/"
  let file = ""
  if c !~ '/'
    let controller = s:controller(1)
    if controller != ''
      let c = controller.'/'.c
    endif
  endif
  if c =~ '\.\w\+\.\w\+$' || c =~ '\.'.s:viewspattern().'$'
    return pre.c
  elseif s:hasfile(pre.c.".rhtml")
    let file = pre.c.".rhtml"
  elseif s:hasfile(pre.c.".rxml")
    let file = pre.c.".rxml"
  else
    let format = "." . s:format('html')
    let vt = s:view_types.","
    while 1
      while vt != ""
        let t = matchstr(vt,'[^,]*')
        let vt = s:sub(vt,'[^,]*,','')
        if s:hasfile(pre.c.format.".".t)
          let file = pre.c.format.".".t
          break
        endif
      endwhile
      if format == '' || file != ''
        break
      else
        let format = ''
      endif
    endwhile
  endif
  return file
endfunction

function! s:findlayout(name)
  return s:findview("layouts/".a:name)
endfunction

function! s:layoutEdit(bang,cmd,...)
  if a:0
    let c = s:underscore(a:1)
  else
    let c = s:controller(1)
  endif
  if c == ""
    let c = "application"
  endif
  let file = s:findlayout(c)
  if file == ""
    let file = s:findlayout("application")
  endif
  if file == ""
    let file = "app/views/layouts/application.rhtml"
  endif
  call s:edit(a:cmd.(a:bang?'!':''),s:sub(file,'^/',''))
endfunction

function! s:controllerEdit(bang,cmd,...)
  let suffix = '.rb'
  if a:0 == 0
    let controller = s:controller(1)
    if RailsFileType() =~ '^view\%(-layout\|-partial\)\@!'
      let suffix = suffix.'#'.expand('%:t:r')
    endif
  else
    let controller = a:1
  endif
  if s:hasfile("app/controllers/".controller."_controller.rb") || !s:hasfile("app/controllers/".controller.".rb")
    let suffix = "_controller".suffix
  endif
  return s:EditSimpleRb(a:bang,a:cmd,"controller",controller,"app/controllers/",suffix)
endfunction

function! s:helperEdit(bang,cmd,...)
  return s:EditSimpleRb(a:bang,a:cmd,"helper",a:0? a:1 : s:controller(1),"app/helpers/","_helper.rb")
endfunction

function! s:apiEdit(bang,cmd,...)
  return s:EditSimpleRb(a:bang,a:cmd,"api",a:0 ? a:1 : s:controller(1),"app/apis/","_api.rb")
endfunction

function! s:stylesheetEdit(bang,cmd,...)
  return s:EditSimpleRb(a:bang,a:cmd,"stylesheet",a:0? a:1 : s:controller(1),"public/stylesheets/",".css")
endfunction

function! s:javascriptEdit(bang,cmd,...)
  return s:EditSimpleRb(a:bang,a:cmd,"javascript",a:0? a:1 : "application","public/javascripts/",".js")
endfunction

function! s:unittestEdit(bang,cmd,...)
  let f = a:0 ? a:1 : s:model(1)
  if !a:0 && RailsFileType() =~ '^model-aro\>' && f != '' && f !~ '_observer$'
    if s:hasfile("test/unit/".f."_observer.rb") || !s:hasfile("test/unit/".f.".rb")
      let f = f . "_observer"
    endif
  endif
  return s:EditSimpleRb(a:bang,a:cmd,"unittest",f,"test/unit/","_test.rb")
endfunction

function! s:functionaltestEdit(bang,cmd,...)
  if a:0
    let f = a:1
  else
    let f = s:controller()
  endif
  if f != '' && !s:hasfile("test/functional/".f."_test.rb")
    if s:hasfile("test/functional/".f."_controller_test.rb")
      let f = f . "_controller"
    elseif s:hasfile("test/functional/".f."_api_test.rb")
      let f = f . "_api"
    endif
  endif
  return s:EditSimpleRb(a:bang,a:cmd,"functionaltest",f,"test/functional/","_test.rb")
endfunction

function! s:integrationtestEdit(bang,cmd,...)
  if a:0
    let f = a:1
  elseif s:model() != ''
    let f = s:model()
  else
    let f = s:controller()
  endif
  return s:EditSimpleRb(a:bang,a:cmd,"integrationtest",f,"test/integration/","_test.rb")
endfunction

function! s:pluginEdit(bang,cmd,...)
  let cmd = s:findcmdfor(a:cmd.(a:bang?'!':''))
  let plugin = ""
  let extra = ""
  if RailsFilePath() =~ '\<vendor/plugins/.'
    let plugin = matchstr(RailsFilePath(),'\<vendor/plugins/\zs[^/]*\ze')
    let extra = "vendor/plugins/" . plugin . "/\n"
  endif
  if a:0
    if a:1 =~ '^[^/.]*/\=$' && s:hasfile("vendor/plugins/".a:1."/init.rb")
      return s:EditSimpleRb(a:bang,a:cmd,"plugin",s:sub(a:1,'/$',''),"vendor/plugins/","/init.rb")
    elseif plugin == ""
      call s:edit(cmd,"vendor/plugins/".s:sub(a:1,'\.$',''))
    elseif a:1 == "."
      call s:findedit(cmd,"vendor/plugins/".plugin)
    elseif isdirectory(RailsRoot()."/vendor/plugins/".matchstr(a:1,'^[^/]*'))
      call s:edit(cmd,"vendor/plugins/".a:1)
    else
      call s:findedit(cmd,"vendor/plugins/".a:1."\nvendor/plugins/".plugin."/".a:1)
    endif
  else
    return s:EditSimpleRb(a:bang,a:cmd,"plugin",plugin,"vendor/plugins/","/init.rb")
  endif
endfunction

function! s:taskEdit(bang,cmd,...)
  let plugin = ""
  let extra = ""
  if RailsFilePath() =~ '\<vendor/plugins/.'
    let plugin = matchstr(RailsFilePath(),'\<vendor/plugins/[^/]*')
    let extra = plugin."/tasks/\n"
  endif
  if a:0
    call s:EditSimpleRb(a:bang,a:cmd,"task",a:1,extra."lib/tasks/",".rake")
  else
    call s:findedit((a:bang ? "!" : ""),(plugin != "" ? plugin."/Rakefile\n" : "")."Rakefile")
  endif
endfunction

function! s:libEdit(bang,cmd,...)
  let extra = ""
  if RailsFilePath() =~ '\<vendor/plugins/.'
    let extra = s:sub(RailsFilePath(),'<vendor/plugins/[^/]*/\zs.*','lib/')."\n"
  endif
  if a:0
    call s:EditSimpleRb(a:bang,a:cmd,"task",a:0? a:1 : "",extra."lib/",".rb")
  else
    " Easter egg
    call s:EditSimpleRb(a:bang,a:cmd,"task","environment","config/",".rb")
  endif
endfunction

" }}}1
" Alternate/Related {{{1

function! s:findcmdfor(cmd)
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
    return num.'tabfind'.bang
  else
    return num.cmd.bang
  endif
endfunction

function! s:editcmdfor(cmd)
  let cmd = s:findcmdfor(a:cmd)
  let cmd = s:sub(cmd,'<sfind>','split')
  let cmd = s:sub(cmd,'find>','edit')
  return cmd
endfunction

function! s:try(cmd) abort
  if !exists(":try")
    " I've seen at least one weird setup without :try
    exe a:cmd
  else
    try
      exe a:cmd
    catch
      call s:error(s:sub(v:exception,'^.{-}:\zeE',''))
      return 0
    endtry
  endif
  return 1
endfunction

function! s:findedit(cmd,file,...) abort
  let cmd = s:findcmdfor(a:cmd)
  if a:file =~ '\n'
    let filelist = a:file . "\n"
    let file = ''
    while file == '' && filelist != ''
      let maybe = matchstr(filelist,'^.\{-\}\ze\n')
      let filelist = s:sub(filelist,'^.{-}\n','')
      if s:hasfile(s:sub(maybe,'[@#].*',''))
        let file = maybe
      endif
    endwhile
    if file == ''
      let file = matchstr(a:file."\n",'^.\{-\}\ze\n')
    endif
  else
    let file = a:file
  endif
  if file =~ '[@#]'
    let djump = matchstr(file,'[@#]\zs.*')
    let file = matchstr(file,'.\{-\}\ze[@#]')
  else
    let djump = ''
  endif
  if file == ''
    let testcmd = "edit"
  elseif RailsRoot() =~ '://' || cmd =~ 'edit' || cmd =~ 'split'
    if file !~ '^/' && file !~ '^\w:' && file !~ '://'
      let file = s:ra().'/'.file
    endif
    let testcmd = s:editcmdfor(cmd).' '.(a:0 ? a:1 . ' ' : '').file
  elseif isdirectory(RailsRoot().'/'.file)
    let testcmd = s:editcmdfor(cmd).' '.(a:0 ? a:1 . ' ' : '').s:ra().'/'.file
    exe testcmd
    return
  else
    let testcmd = cmd.' '.(a:0 ? a:1 . ' ' : '').file
  endif
  if s:try(testcmd)
    " Shorten the file name (I don't fully understand how Vim decides when to
    " use a relative/absolute path for the file name, so lets blindly force it
    " to be as short as possible)
    "silent! file %:~:.
    "silent! lcd .
    call s:djump(djump)
  endif
endfunction

function! s:edit(cmd,file,...)
  let cmd = s:editcmdfor(a:cmd)
  let cmd = cmd.' '.(a:0 ? a:1 . ' ' : '')
  let file = a:file
  if file !~ '^/' && file !~ '^\w:' && file !~ '://'
    "let file = s:ra().'/'.file
    exe cmd."`=RailsRoot().'/'.file`"
  else
    exe cmd.file
  endif
  "exe cmd.file
endfunction

function! s:Alternate(bang,cmd)
  let cmd = a:cmd.(a:bang?"!":"")
  let file = s:AlternateFile()
  if file != ""
    call s:findedit(cmd,file)
  else
    call s:warn("No alternate file is defined")
  endif
endfunction

function! s:AlternateFile()
  let f = RailsFilePath()
  let t = RailsFileType()
  let altopt = s:getopt("alternate","bl")
  if altopt != ""
    return altopt
  elseif f =~ '\<config/environments/'
    return "config/environment.rb"
  elseif f == 'README'
    return "config/database.yml"
  elseif f =~ '\<config/database\.yml$'   | return "config/routes.rb"
  elseif f =~ '\<config/routes\.rb$'      | return "config/environment.rb"
  elseif f =~ '\<config/environment\.rb$' | return "config/database.yml"
  elseif f =~ '\<db/migrate/\d\d\d_'
    let num = matchstr(f,'\<db/migrate/0*\zs\d\+\ze_')-1
    return num ? s:migrationfor(num) : "db/schema.rb"
  elseif f =~ '\<application\.js$'
    return "app/helpers/application_helper.rb"
  elseif t =~ '^js\>'
    return "public/javascripts/application.js"
  elseif f =~ '\<db/schema\.rb$'
    return s:migrationfor("")
  elseif t =~ '^view\>'
    if t =~ '\<layout\>'
      let dest = fnamemodify(f,':r:s?/layouts\>??').'/layout.'.fnamemodify(f,':e')
    else
      let dest = f
    endif
    " Go to the (r)spec, helper, controller, or (mailer) model
    let spec       = fnamemodify(dest,':r:s?\<app/?spec/?')."_view_spec.rb"
    let helper     = fnamemodify(dest,':h:s?/views/?/helpers/?')."_helper.rb"
    let controller = fnamemodify(dest,':h:s?/views/?/controllers/?')."_controller.rb"
    let model      = fnamemodify(dest,':h:s?/views/?/models/?').".rb"
    if s:hasfile(spec)
      return spec
    elseif s:hasfile(helper)
      return helper
    elseif s:hasfile(controller)
      let jumpto = expand("%:t:r")
      return controller.'#'.jumpto
    elseif s:hasfile(model)
      return model
    else
      return helper
    endif
  elseif t =~ '^controller-api\>'
    let api = s:sub(s:sub(f,'/controllers/','/apis/'),'_controller\.rb$','_api.rb')
    return api
  elseif t =~ '^helper\>'
    let controller = s:sub(s:sub(f,'/helpers/','/controllers/'),'_helper\.rb$','_controller.rb')
    let controller = s:sub(controller,'application_controller','application')
    let spec = s:sub(s:sub(f,'<app/','spec/'),'\.rb$','_spec.rb')
    if s:hasfile(spec)
      return spec
    else
      return controller
    endif
  elseif t =~ '\<fixtures\>' && f =~ '\<spec/'
    let file = s:singularize(expand("%:t:r")).'_spec.rb'
    return file
  elseif t =~ '\<fixtures\>'
    let file = s:singularize(expand("%:t:r")).'_test.rb' " .expand('%:e')
    return file
  elseif f == ''
    call s:warn("No filename present")
  elseif f =~ '\<test/unit/routing_test\.rb$'
    return 'config/routes.rb'
  elseif t=~ '^spec-view\>'
    return s:sub(s:sub(f,'<spec/','app/'),'_view_spec\.rb$','')
  elseif fnamemodify(f,":e") == "rb"
    let file = fnamemodify(f,":r")
    if file =~ '_\%(test\|spec\)$'
      let file = s:sub(file,'_%(test|spec)$','.rb')
    else
      let file = file.'_test.rb'
    endif
    if t =~ '^model\>'
      return s:sub(file,'app/models/','test/unit/')."\n".s:sub(s:sub(file,'_test\.rb$','_spec.rb'),'app/models/','spec/models/')
    elseif t =~ '^controller\>'
      "return s:sub(file,'app/controllers/','test/functional/')
      return s:sub(file,'<app/controllers/','test/functional/')."\n".s:sub(s:sub(file,'_test\.rb$','_spec.rb'),'app/controllers/','spec/controllers/')
    elseif t =~ '^test-unit\>'
      return s:sub(file,'test/unit/','app/models/')
    elseif t =~ '^test-functional\>'
      if file =~ '_api\.rb'
        return s:sub(file,'test/functional/','app/apis/')
      elseif file =~ '_controller\.rb'
        return s:sub(file,'test/functional/','app/controllers/')
      else
        return s:sub(file,'test/functional/','')
      endif
    elseif t =~ '^spec\>'
      return s:sub(file,'<spec/','app/')
    elseif file =~ '\<vendor/.*/lib/'
      return s:sub(file,'<vendor/.{-}/\zslib/','test/')
    elseif file =~ '\<vendor/.*/test/'
      return s:sub(file,'<vendor/.{-}/\zstest/','lib/')
    else
      return fnamemodify(file,":t")
    endif
  else
    return ""
  endif
endfunction

function! s:Related(bang,cmd)
  let cmd = a:cmd.(a:bang?"!":"")
  let file = s:RelatedFile()
  if file != ""
    call s:findedit(cmd,file)
  else
    call s:warn("No related file is defined")
  endif
endfunction

function! s:RelatedFile()
  let f = RailsFilePath()
  let t = RailsFileType()
  let lastmethod = s:lastmethod()
  if s:getopt("related","l") != ""
    return s:getopt("related","l")
  elseif t =~ '^\%(controller\|model-mailer\)\>' && lastmethod != ""
    let root = s:sub(s:sub(s:sub(f,'/application\.rb$','/shared_controller.rb'),'/%(controllers|models)/','/views/'),'%(_controller)=\.rb$','/'.lastmethod)
    let format = s:format('html')
    if glob(RailsRoot().'/'.root.'.'.format.'.*[^~]') != ''
      return root . '.' . format
    else
      return root
    endif
  elseif s:getopt("related","b") != ""
    return s:getopt("related","b")
  elseif f =~ '\<config/environments/'
    return "config/database.yml#". expand("%:t:r")
  elseif f == 'README'
    return "config/database.yml"
  elseif f =~ '\<config/database\.yml$'
    let lm = s:lastmethod()
    if lm != ""
      return "config/environments/".lm.".rb\nconfig/environment.rb"
    else
      return "config/environment.rb"
    endif
  elseif f =~ '\<config/routes\.rb$'      | return "config/database.yml"
  elseif f =~ '\<config/environment\.rb$' | return "config/routes.rb"
  elseif f =~ '\<db/migrate/\d\d\d_'
    let num = matchstr(f,'\<db/migrate/0*\zs\d\+\ze_')+1
    let migr = s:migrationfor(num)
    return migr == '' ? "db/schema.rb" : migr
  elseif t =~ '^test\>' && f =~ '\<test/\w\+/'
    let target = s:sub(f,'.*<test/\w+/','test/mocks/test/')
    let target = s:sub(target,'_test\.rb$','.rb')
    return target
  elseif f =~ '\<application\.js$'
    return "app/helpers/application_helper.rb"
  elseif t =~ '^js\>'
    return "public/javascripts/application.js"
  elseif t =~ '^view-layout\>'
    return s:sub(s:sub(s:sub(f,'/views/','/controllers/'),'/layouts/(\k+)\..*$','/\1_controller.rb'),'<application_controller\.rb$','application.rb')
  "elseif t=~ '^view-partial\>'
    "call s:warn("No related file is defined")
  elseif t =~ '^view\>'
    let controller  = s:sub(s:sub(f,'/views/','/controllers/'),'/(\k+%(\.\k+)=)\..*$','_controller.rb#\1')
    let controller2 = s:sub(s:sub(f,'/views/','/controllers/'),'/(\k+%(\.\k+)=)\..*$','.rb#\1')
    let model       = s:sub(s:sub(f,'/views/','/models/'),'/(\k+)\..*$','.rb#\1')
    if filereadable(s:sub(controller,'#.{-}$',''))
      return controller
    elseif filereadable(s:sub(controller2,'#.{-}$',''))
      return controller2
    elseif filereadable(s:sub(model,'#.{-}$','')) || model =~ '_mailer\.rb#'
      return model
    else
      return controller
    endif
  elseif t =~ '^controller-api\>'
    return s:sub(s:sub(f,'/controllers/','/apis/'),'_controller\.rb$','_api.rb')
  elseif t =~ '^controller\>'
    return s:sub(s:sub(f,'/controllers/','/helpers/'),'%(_controller)=\.rb$','_helper.rb')
  elseif t=~ '^helper\>'
      return s:sub(s:sub(f,'/helpers/','/views/layouts/'),'%(_helper)=\.rb$','')
  elseif t =~ '^model-arb\>'
    "call s:migrationEdit(0,cmd,'create_'.s:pluralize(expand('%:t:r')))
    return s:migrationfor('create_'.s:pluralize(expand('%:t:r')))
  elseif t =~ '^model-aro\>'
    return s:sub(f,'_observer\.rb$','.rb')
  elseif t =~ '^api\>'
    return s:sub(s:sub(f,'/apis/','/controllers/'),'_api\.rb$','_controller.rb')
  elseif f =~ '\<db/schema\.rb$'
    return s:migrationfor(1)
  else
    "call s:warn("No related file is defined")
    return ""
  endif
endfunction

" }}}1
" Partial Extraction {{{1

" Depends: s:error, s:sub, s:viewspattern, s:warn

function! s:Extract(bang,...) range abort
  if a:0 == 0 || a:0 > 1
    return s:error("Incorrect number of arguments")
  endif
  if a:1 =~ '[^a-z0-9_/.]'
    return s:error("Invalid partial name")
  endif
  let rails_root = RailsRoot()
  let ext = expand("%:e")
  let file = a:1
  let first = a:firstline
  let last = a:lastline
  let range = first.",".last
  if RailsFileType() =~ '^view-layout\>'
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
  let curdir = rails_root."/".curdir
  let dir = fnamemodify(file,":h")
  let fname = fnamemodify(file,":t")
  if fnamemodify(fname,":e") == ""
    let name = fname
    let fname = fname.".".matchstr(expand("%:t"),'\.\zs.*')
  elseif fnamemodify(fname,":e") !~ '^'.s:viewspattern().'$'
    let name = fnamemodify(fname,":r")
    let fname = fname.".".ext
  else
    let name = fnamemodify(fname,":r:r")
  endif
  let var = "@".name
  let collection = ""
  if dir =~ '^/'
    let out = (rails_root).dir."/_".fname
  elseif dir == ""
    let out = (curdir)."/_".fname
  elseif isdirectory(curdir."/".dir)
    let out = (curdir)."/".dir."/_".fname
  else
    let out = (rails_root)."/app/views/".dir."/_".fname
  endif
  if filereadable(out)
    let partial_warn = 1
    "echoerr "Partial exists"
    "return
  endif
  if bufnr(out) > 0
    if bufloaded(out)
      return s:error("Partial already open in buffer ".bufnr(out))
    else
      exe "bwipeout ".bufnr(out)
    endif
  endif
  " No tabs, they'll just complicate things
  if ext =~? '^\%(rhtml\|erb\|dryml\)$'
    let erub1 = '\<\%\s*'
    let erub2 = '\s*-=\%\>'
  else
    let erub1 = ''
    let erub2 = ''
  endif
  let spaces = matchstr(getline(first),"^ *")
  if getline(last+1) =~ '\v^\s*'.erub1.'end'.erub2.'\s*$'
    let fspaces = matchstr(getline(last+1),"^ *")
    if getline(first-1) =~ '\v^'.fspaces.erub1.'for\s+(\k+)\s+in\s+([^ %>]+)'.erub2.'\s*$'
      let collection = s:sub(getline(first-1),'^'.fspaces.erub1.'for\s+(\k+)\s+in\s+([^ >]+)'.erub2.'\s*$','\1>\2')
    elseif getline(first-1) =~ '\v^'.fspaces.erub1.'([^ %>]+)\.each\s+do\s+\|\s*(\k+)\s*\|'.erub2.'\s*$'
      let collection = s:sub(getline(first-1),'^'.fspaces.erub1.'([^ %>]+)\.each\s+do\s+\|\s*(\k+)\s*\|'.erub2.'\s*$','\2>\1')
    endif
    if collection != ''
      let var = matchstr(collection,'^\k\+')
      let collection = s:sub(collection,'^\k+\>','')
      let first = first - 1
      let last = last + 1
    endif
  else
    let fspaces = spaces
  endif
  "silent exe range."write ".out
  let renderstr = "render :partial => '".fnamemodify(file,":r:r")."'"
  if collection != ""
    let renderstr = renderstr.", :collection => ".collection
  elseif "@".name != var
    let renderstr = renderstr.", :object => ".var
  endif
  if ext =~? '^\%(rhtml\|erb\|dryml\)$'
    let renderstr = "<%= ".renderstr." %>"
  elseif ext == "rxml" || ext == "builder"
    let renderstr = "xml << ".s:sub(renderstr,"render ","render(").")"
  elseif ext == "rjs"
    let renderstr = "page << ".s:sub(renderstr,"render ","render(").")"
  elseif ext == "haml"
    let renderstr = "= ".renderstr
  elseif ext == "mn"
    let renderstr = "_".renderstr
  endif
  let buf = @@
  silent exe range."yank"
  let partial = @@
  let @@ = buf
  let ai = &ai
  let &ai = 0
  silent exe "norm! :".first.",".last."change\<CR>".fspaces.renderstr."\<CR>.\<CR>"
  let &ai = ai
  if renderstr =~ '<%'
    norm ^6w
  else
    norm ^5w
  endif
  let ft = &ft
  if &hidden
    enew
  else
    new
  endif
  let shortout = fnamemodify(out,':~:.')
  "exe "silent file ".s:escarg(shortout)
  silent file `=shortout`
  let &ft = ft
  let @@ = partial
  silent put
  0delete
  let @@ = buf
  if spaces != ""
    silent! exe '%substitute/^'.spaces.'//'
  endif
  silent! exe '%substitute?\%(\w\|[@:"'."'".'-]\)\@<!'.var.'\>?'.name.'?g'
  1
  call RailsBufInit(rails_root)
  if exists("l:partial_warn")
    call s:warn("Warning: partial exists!")
  endif
endfunction

" }}}1
" Migration Inversion {{{1

" Depends: s:sub, s:endof, s:gsub, s:error

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
      let add = add.s:mkeep(line)
    elseif line =~ '\<remove_index\>'
      let add = s:sub(s:sub(line,'<remove_index','add_index'),':column\s*=>\s*','')
    elseif line =~ '\<rename_\%(table\|column\)\>'
      let add = s:sub(line,'<rename_%(table\s*\(=\s*|column\s*\(=\s*[^,]*,\s*)\zs([^,]*)(,\s*)([^,]*)','\3\2\1')
    elseif line =~ '\<change_column\>'
      let add = s:migspc(line).'change_column'.s:mextargs(line,2).s:mkeep(line)
    elseif line =~ '\<change_column_default\>'
      let add = s:migspc(line).'change_column_default'.s:mextargs(line,2).s:mkeep(line)
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
      let add = s:sub(line,'^\s*\zs.*','raise ActiveRecord::IrreversableMigration')
    elseif add == " "
      let add = ""
    endif
    let str = add."\n".str
    let lnum = lnum + 1
  endwhile
  let str = s:gsub(str,'(\s*raise ActiveRecord::IrreversableMigration\n)+','\1')
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
  if beg + 1 < end
    exe (beg+1).",".(end-1)."delete _"
  endif
  if str != ""
    let reg_keep = @"
    let @" = str
    exe beg."put"
    exe 1+beg
    let @" = reg_keep
  endif
endfunction

" }}}1
" Cache {{{1

function! s:cacheworks()
  if v:version < 700 || RailsRoot() == ""
    return 0
  endif
  if !exists("s:cache")
    let s:cache = {}
  endif
  if !has_key(s:cache,RailsRoot())
    let s:cache[RailsRoot()] = {}
  endif
  return 1
endfunction

function! s:cacheclear(...)
  if RailsRoot() == "" | return "" | endif
  if !s:cacheworks() | return "" | endif
  if a:0 == 1
    if s:cachehas(a:1)
      unlet! s:cache[RailsRoot()][a:1]
    endif
  else
    let s:cache[RailsRoot()] = {}
  endif
endfunction

function! s:cache(...)
  if !s:cacheworks() | return "" | endif
  if a:0 == 1
    return s:cache[RailsRoot()][a:1]
  else
    return s:cache[RailsRoot()]
  endif
endfunction

"function! RailsCache(...)
  "if !s:cacheworks() | return "" | endif
  "if a:0 == 1
    "if s:cachehas(a:1)
      "return s:cache(a:1)
    "else
      "return ""
    "endif
  "else
    "return s:cache()
  "endif
"endfunction

function! s:cachehas(key)
  if !s:cacheworks() | return "" | endif
  return has_key(s:cache(),a:key)
endfunction

function! s:cacheneeds(key)
  if !s:cacheworks() | return "" | endif
  return !has_key(s:cache(),a:key)
endfunction

function! s:cacheset(key,value)
  if !s:cacheworks() | return "" | endif
  let s:cache[RailsRoot()][a:key] = a:value
endfunction

" }}}1
" Syntax {{{1

" Depends: s:rubyeval, s:gsub, cache functions

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
  let s:rails_helper_methods = ""
        \."atom_feed auto_discovery_link_tag auto_link "
        \."benchmark button_to button_to_function "
        \."cache capture cdata_section check_box check_box_tag collection_select concat content_for content_tag content_tag_for country_options_for_select country_select cycle "
        \."date_select datetime_select debug define_javascript_functions distance_of_time_in_words distance_of_time_in_words_to_now div_for dom_class dom_id draggable_element draggable_element_js drop_receiving_element drop_receiving_element_js "
        \."error_message_on error_messages_for escape_javascript escape_once evaluate_remote_response excerpt "
        \."field_set_tag fields_for file_field file_field_tag form form_for form_remote_for form_remote_tag form_tag "
        \."hidden_field hidden_field_tag highlight "
        \."image_path image_submit_tag image_tag input "
        \."javascript_cdata_section javascript_include_tag javascript_path javascript_tag "
        \."label label_tag link_to link_to_function link_to_if link_to_remote link_to_unless link_to_unless_current "
        \."mail_to markdown "
        \."number_to_currency number_to_human_size number_to_percentage number_to_phone number_with_delimiter number_with_precision "
        \."observe_field observe_form option_groups_from_collection_for_select options_for_select options_from_collection_for_select "
        \."partial_path password_field password_field_tag path_to_image path_to_javascript path_to_stylesheet periodically_call_remote pluralize "
        \."radio_button radio_button_tag remote_form_for remote_function reset_cycle "
        \."sanitize sanitize_css select select_date select_datetime select_day select_hour select_minute select_month select_second select_tag select_time select_year simple_format sortable_element sortable_element_js strip_links strip_tags stylesheet_link_tag stylesheet_path submit_tag submit_to_remote "
        \."tag text_area text_area_tag text_field text_field_tag textilize textilize_without_paragraph time_ago_in_words time_select time_zone_options_for_select time_zone_select truncate "
        \."update_page update_page_tag url_for "
        \."visual_effect "
        \."word_wrap"

  " The list of helper methods used to be derived automatically.  Let's keep
  " this code around in case it's needed again.
  if !exists("s:rails_helper_methods")
    if g:rails_expensive
      let s:rails_helper_methods = ""
      if has("ruby")
        " && (has("win32") || has("win32unix"))
        ruby begin; require 'rubygems'; rescue LoadError; end
        if exists("g:rubycomplete_rails") && g:rubycomplete_rails
          ruby begin; require VIM::evaluate('RailsRoot()')+'/config/environment'; rescue Exception; end
        else
          ruby begin; require 'active_support'; require 'action_controller'; require 'action_view'; rescue LoadError; end
        end
        ruby begin; h = ActionView::Helpers.constants.grep(/Helper$/).collect {|c|ActionView::Helpers.const_get c}.collect {|c| c.public_instance_methods(false)}.collect {|es| es.reject {|e| e =~ /_with(out)?_deprecation$/ || es.include?("#{e}_without_deprecation")}}.flatten.sort.uniq.reject {|m| m =~ /[=?!]$/}; VIM::command('let s:rails_helper_methods = "%s"' % h.join(" ")); rescue Exception; end
      endif
      if s:rails_helper_methods == ""
        let s:rails_helper_methods = s:rubyeval('require %{action_controller}; require %{action_view}; h = ActionView::Helpers.constants.grep(/Helper$/).collect {|c|ActionView::Helpers.const_get c}.collect {|c| c.public_instance_methods(false)}.collect {|es| es.reject {|e| e =~ /_with(out)?_deprecation$/ || es.include?(%{#{e}_without_deprecation})}}.flatten.sort.uniq.reject {|m| m =~ /[=?!]$/}; puts h.join(%{ })',"link_to")
      endif
    else
      let s:rails_helper_methods = "link_to"
    endif
  endif
  "let g:rails_helper_methods = s:rails_helper_methods
  return s:rails_helper_methods
endfunction

function! s:BufSyntax()
  if (!exists("g:rails_syntax") || g:rails_syntax)
    let t = RailsFileType()
    let s:prototype_functions = "$ $$ $A $F $H $R $w"
    " From the Prototype bundle for TextMate
    let s:prototype_classes = "Prototype Class Abstract Try PeriodicalExecuter Enumerable Hash ObjectRange Element Ajax Responders Base Request Updater PeriodicalUpdater Toggle Insertion Before Top Bottom After ClassNames Form Serializers TimedObserver Observer EventObserver Event Position Effect Effect2 Transitions ScopedQueue Queues DefaultOptions Parallel Opacity Move MoveBy Scale Highlight ScrollTo Fade Appear Puff BlindUp BlindDown SwitchOff DropOut Shake SlideDown SlideUp Squish Grow Shrink Pulsate Fold"

    let rails_helper_methods = '+\.\@<!\<\('.s:gsub(s:helpermethods(),'\s+','\\|').'\)\>+'
    let classes = s:gsub(RailsUserClasses(),'::',' ')
    if &syntax == 'ruby'
      if classes != ''
        exe "syn keyword rubyRailsUserClass ".classes." containedin=rubyClassDeclaration,rubyModuleDeclaration,rubyClass,rubyModule"
      endif
      if t == ''
        syn keyword rubyRailsMethod params request response session headers cookies flash
      endif
      if t =~ '^api\>'
        syn keyword rubyRailsAPIMethod api_method inflect_names
      endif
      if t =~ '^model$' || t =~ '^model-arb\>'
        syn keyword rubyRailsARMethod acts_as_list acts_as_nested_set acts_as_tree composed_of serialize
        syn keyword rubyRailsARAssociationMethod belongs_to has_one has_many has_and_belongs_to_many
        "syn match rubyRailsARCallbackMethod '\<\(before\|after\)_\(create\|destroy\|save\|update\|validation\|validation_on_create\|validation_on_update\)\>'
        syn keyword rubyRailsARCallbackMethod before_create before_destroy before_save before_update before_validation before_validation_on_create before_validation_on_update
        syn keyword rubyRailsARCallbackMethod after_create after_destroy after_save after_update after_validation after_validation_on_create after_validation_on_update
        syn keyword rubyRailsARClassMethod attr_accessible attr_protected establish_connection set_inheritance_column set_locking_column set_primary_key set_sequence_name set_table_name
        "syn keyword rubyRailsARCallbackMethod after_find after_initialize
        syn keyword rubyRailsARValidationMethod validate validate_on_create validate_on_update validates_acceptance_of validates_associated validates_confirmation_of validates_each validates_exclusion_of validates_format_of validates_inclusion_of validates_length_of validates_numericality_of validates_presence_of validates_size_of validates_uniqueness_of
        syn keyword rubyRailsMethod logger
      endif
      if t =~ '^model-aro\>'
        syn keyword rubyRailsARMethod observe
      endif
      if t =~ '^model-mailer\>'
        syn keyword rubyRailsMethod logger
        " Misnomer but who cares
        syn keyword rubyRailsControllerMethod helper helper_attr helper_method
      endif
      if t =~ '^controller\>' || t =~ '^view\>' || t=~ '^helper\>'
        syn keyword rubyRailsMethod params request response session headers cookies flash
        syn match rubyRailsError '[@:]\@<!@\%(params\|request\|response\|session\|headers\|cookies\|flash\)\>'
        syn match rubyRailsError '\<\%(render_partial\|puts\)\>'
        syn keyword rubyRailsRenderMethod render
        syn keyword rubyRailsMethod logger
      endif
      if t =~ '^helper\>' || t=~ '^view\>'
        "exe "syn match rubyRailsHelperMethod ".rails_helper_methods
        exe "syn keyword rubyRailsHelperMethod ".s:sub(s:helpermethods(),'<select\s+','')
        syn match rubyRailsHelperMethod '\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!'
        syn match rubyRailsViewMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\|controller\)\>'
        if t =~ '\<partial\>'
          syn keyword rubyRailsMethod local_assigns
        endif
        "syn keyword rubyRailsDeprecatedMethod start_form_tag end_form_tag link_to_image human_size update_element_function
      elseif t =~ '^controller\>'
        syn keyword rubyRailsControllerMethod helper helper_attr helper_method filter layout url_for serialize exempt_from_layout filter_parameter_logging hide_action cache_sweeper
        syn match rubyRailsDeprecatedMethod '\<render_\%(action\|text\|file\|template\|nothing\|without_layout\)\>'
        syn keyword rubyRailsRenderMethod render_to_string redirect_to head
        syn match   rubyRailsRenderMethod '\<respond_to\>?\@!'
        syn keyword rubyRailsFilterMethod before_filter append_before_filter prepend_before_filter after_filter append_after_filter prepend_after_filter around_filter append_around_filter prepend_around_filter skip_before_filter skip_after_filter
        syn keyword rubyRailsFilterMethod verify
      endif
      if t =~ '^\%(db-\)\=\%(migration\|schema\)\>'
        syn keyword rubyRailsMigrationMethod create_table drop_table rename_table add_column rename_column change_column change_column_default remove_column add_index remove_index
      endif
      if t =~ '^test\>'
        if s:cacheneeds("user_asserts") && filereadable(RailsRoot()."/test/test_helper.rb")
          call s:cacheset("user_asserts",map(filter(readfile(RailsRoot()."/test/test_helper.rb"),'v:val =~ "^  def assert_"'),'matchstr(v:val,"^  def \\zsassert_\\w\\+")'))
        endif
        if s:cachehas("user_asserts") && !empty(s:cache("user_asserts"))
          exe "syn keyword rubyRailsUserMethod ".join(s:cache("user_asserts"))
        endif
        syn keyword rubyRailsTestMethod add_assertion assert assert_block assert_equal assert_in_delta assert_instance_of assert_kind_of assert_match assert_nil assert_no_match assert_not_equal assert_not_nil assert_not_same assert_nothing_raised assert_nothing_thrown assert_operator assert_raise assert_respond_to assert_same assert_send assert_throws assert_recognizes assert_generates assert_routing flunk fixtures fixture_path use_transactional_fixtures use_instantiated_fixtures assert_difference assert_no_difference assert_valid
        if t !~ '^test-unit\>'
          syn match   rubyRailsTestControllerMethod  '\.\@<!\<\%(get\|post\|put\|delete\|head\|process\|assigns\)\>'
          syn keyword rubyRailsTestControllerMethod assert_response assert_redirected_to assert_template assert_recognizes assert_generates assert_routing assert_dom_equal assert_dom_not_equal assert_select assert_select_rjs assert_select_encoded assert_select_email assert_tag assert_no_tag
        endif
      elseif t=~ '^spec\>'
        syn keyword rubyRailsTestMethod describe context it specify it_should_behave_like before after fixtures controller_name helper_name
        syn keyword rubyRailsTestMethod violated pending
        if t !~ '^spec-model\>'
          syn match   rubyRailsTestControllerMethod  '\.\@<!\<\%(get\|post\|put\|delete\|head\|process\|assigns\)\>'
          syn keyword rubyRailsMethod params request response session flash
        endif
      endif
      if t =~ '^task\>'
        syn match rubyRailsRakeMethod '^\s*\zs\%(task\|file\|namespace\|desc\|before\|after\|on\)\>\%(\s*=\)\@!'
      endif
      if t =~ '^model-awss\>'
        syn keyword rubyRailsMethod member
      endif
      if t =~ '^config-routes\>'
        syn match rubyRailsMethod '\.\zs\%(connect\|resources\=\|root\|named_route\|namespace\)\>'
      endif
      syn keyword rubyRailsMethod debugger
      syn keyword rubyRailsMethod alias_attribute alias_method_chain attr_accessor_with_default attr_internal attr_internal_accessor attr_internal_reader attr_internal_writer delegate mattr_accessor mattr_reader mattr_writer
      syn keyword rubyRailsMethod cattr_accessor cattr_reader cattr_writer class_inheritable_accessor class_inheritable_array class_inheritable_array_writer class_inheritable_hash class_inheritable_hash_writer class_inheritable_option class_inheritable_reader class_inheritable_writer inheritable_attributes read_inheritable_attribute reset_inheritable_attributes write_inheritable_array write_inheritable_attribute write_inheritable_hash
      syn keyword rubyRailsInclude require_dependency gem

      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:order\s*=>\s*\)\@<="+ skip=+\\\\\|\\"+ end=+"+ contains=@rubyStringSpecial,railsOrderSpecial
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:order\s*=>\s*\)\@<='+ skip=+\\\\\|\\'+ end=+'+ contains=@rubyStringSpecial,railsOrderSpecial
      syn match   railsOrderSpecial +\c\<\%(DE\|A\)SC\>+ contained
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:conditions\s*=>\s*\[\s*\)\@<="+ skip=+\\\\\|\\"+ end=+"+ contains=@rubyStringSpecial,railsConditionsSpecial
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:conditions\s*=>\s*\[\s*\)\@<='+ skip=+\\\\\|\\'+ end=+'+ contains=@rubyStringSpecial,railsConditionsSpecial
      syn match   railsConditionsSpecial +?\|:\h\w*+ contained
      syn cluster rubyNotTop add=railsOrderSpecial,railsConditionsSpecial

      " XHTML highlighting inside %Q<>
      unlet! b:current_syntax
      let removenorend = !exists("g:html_no_rendering")
      let g:html_no_rendering = 1
      syn include @htmlTop syntax/xhtml.vim
      if removenorend
          unlet! g:html_no_rendering
      endif
      let b:current_syntax = "ruby"
      " Restore syn sync, as best we can
      if !exists("g:ruby_minlines")
        let g:ruby_minlines = 50
      endif
      syn sync fromstart
      exe "syn sync minlines=" . g:ruby_minlines
      syn case match
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+%Q\=<+ end=+>+ contains=@htmlTop,@rubyStringSpecial
      "syn region  rubyString   matchgroup=rubyStringDelimiter start=+%q<+ end=+>+ contains=@htmlTop
      syn cluster htmlArgCluster add=@rubyStringSpecial
      syn cluster htmlPreProc    add=@rubyStringSpecial

    elseif &syntax == "eruby" || &syntax == "haml"
      syn case match
      if classes != ''
        exe "syn keyword erubyRailsUserClass ".classes." contained containedin=@erubyRailsRegions"
      endif
      if &syntax == "haml"
        syn cluster erubyRailsRegions contains=hamlRubyCodeIncluded,hamlRubyCode,hamlRubyHash,@hamlEmbeddedRuby,rubyInterpolation
      else
        syn cluster erubyRailsRegions contains=erubyOneLiner,erubyBlock,erubyExpression,rubyInterpolation
      endif
      syn match rubyRailsError '[@:]\@<!@\%(params\|request\|response\|session\|headers\|cookies\|flash\)\>' contained containedin=@erubyRailsRegions
      exe "syn keyword erubyRailsHelperMethod ".s:sub(s:helpermethods(),'<select\s+','')." contained containedin=@erubyRailsRegions"
      syn match erubyRailsHelperMethod '\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!' contained containedin=@erubyRailsRegions
      syn keyword erubyRailsMethod debugger logger contained containedin=@erubyRailsRegions
      syn keyword erubyRailsMethod params request response session headers cookies flash contained containedin=@erubyRailsRegions
      syn match erubyRailsViewMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\|controller\)\>' contained containedin=@erubyRailsRegions
      if t =~ '\<partial\>'
        syn keyword erubyRailsMethod local_assigns contained containedin=@erubyRailsRegions
      endif
      syn keyword erubyRailsRenderMethod render contained containedin=@erubyRailsRegions
      syn match rubyRailsError '[^@:]\@<!@\%(params\|request\|response\|session\|headers\|cookies\|flash\)\>' contained containedin=@erubyRailsRegions
      syn match rubyRailsError '\<\%(render_partial\|puts\)\>' contained containedin=@erubyRailsRegions
      syn case match
      set isk+=$
      exe "syn keyword javascriptRailsClass contained ".s:prototype_classes
      exe "syn keyword javascriptRailsFunction contained ".s:prototype_functions
      syn cluster htmlJavaScript add=javascriptRailsClass,javascriptRailsFunction
    elseif &syntax == "yaml"
      syn case match
      " Modeled after syntax/eruby.vim
      unlet! b:current_syntax
      let g:main_syntax = 'eruby'
      syn include @rubyTop syntax/ruby.vim
      unlet g:main_syntax
      syn cluster yamlRailsRegions contains=yamlRailsOneLiner,yamlRailsBlock,yamlRailsExpression
      syn region  yamlRailsOneLiner   matchgroup=yamlRailsDelimiter start="^%%\@!" end="$"  contains=@rubyRailsTop	containedin=ALLBUT,@yamlRailsRegions,yamlRailsComment keepend oneline
      syn region  yamlRailsBlock      matchgroup=yamlRailsDelimiter start="<%%\@!" end="%>" contains=@rubyTop		containedin=ALLBUT,@yamlRailsRegions,yamlRailsComment
      syn region  yamlRailsExpression matchgroup=yamlRailsDelimiter start="<%="    end="%>" contains=@rubyTop		containedin=ALLBUT,@yamlRailsRegions,yamlRailsComment
      syn region  yamlRailsComment    matchgroup=yamlRailsDelimiter start="<%#"    end="%>" contains=rubyTodo,@Spell	containedin=ALLBUT,@yamlRailsRegions,yamlRailsComment keepend
      syn match yamlRailsMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' contained containedin=@yamlRailsRegions
      if classes != ''
        exe "syn keyword yamlRailsUserClass ".classes." contained containedin=@yamlRailsRegions"
      endif
      let b:current_syntax = "yaml"
    elseif &syntax == "html"
      syn case match
      set isk+=$
      exe "syn keyword javascriptRailsClass contained ".s:prototype_classes
      exe "syn keyword javascriptRailsFunction contained ".s:prototype_functions
      syn cluster htmlJavaScript add=javascriptRailsClass,javascriptRailsFunction
    elseif &syntax == "javascript"
      " The syntax file included with Vim incorrectly sets syn case ignore.
      syn case match
      set isk+=$
      exe "syn keyword javascriptRailsClass ".s:prototype_classes
      exe "syn keyword javascriptRailsFunction ".s:prototype_functions

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
  hi def link rubyRailsDeprecatedMethod       rubyRailsError
  hi def link rubyRailsFilterMethod           rubyRailsMethod
  hi def link rubyRailsTestControllerMethod   rubyRailsTestMethod
  hi def link rubyRailsTestMethod             rubyRailsMethod
  hi def link rubyRailsRakeMethod             rubyRailsMethod
  hi def link rubyRailsMethod                 railsMethod
  hi def link rubyRailsError                  rubyError
  hi def link rubyRailsInclude                rubyInclude
  hi def link rubyRailsUserClass              railsUserClass
  hi def link rubyRailsUserMethod             railsUserMethod
  hi def link erubyRailsHelperMethod          erubyRailsMethod
  hi def link erubyRailsViewMethod            erubyRailsMethod
  hi def link erubyRailsRenderMethod          erubyRailsMethod
  hi def link erubyRailsMethod                railsMethod
  hi def link erubyRailsUserMethod            railsUserMethod
  hi def link railsUserMethod                 railsMethod
  hi def link erubyRailsUserClass             railsUserClass
  hi def link yamlRailsDelimiter              Delimiter
  hi def link yamlRailsMethod                 railsMethod
  hi def link yamlRailsComment                Comment
  hi def link yamlRailsUserClass              railsUserClass
  hi def link yamlRailsUserMethod             railsUserMethod
  hi def link javascriptRailsFunction         railsMethod
  hi def link javascriptRailsClass            railsClass
  hi def link railsUserClass                  railsClass
  hi def link railsMethod                     Function
  hi def link railsClass                      Type
  hi def link railsOrderSpecial               railsStringSpecial
  hi def link railsConditionsSpecial          railsStringSpecial
  hi def link railsStringSpecial              Identifier
endfunction

function! RailslogSyntax()
  syn match   railslogRender      '^\s*\<\%(Processing\|Rendering\|Rendered\|Redirected\|Completed\)\>'
  syn match   railslogComment     '^\s*# .*'
  syn match   railslogModel       '^\s*\u\%(\w\|:\)* \%(Load\%( Including Associations\| IDs For Limited Eager Loading\)\=\|Columns\|Count\|Update\|Destroy\|Delete all\)\>' skipwhite nextgroup=railslogModelNum
  syn match   railslogModel       '^\s*SQL\>' skipwhite nextgroup=railslogModelNum
  syn region  railslogModelNum    start='(' end=')' contains=railslogNumber contained skipwhite nextgroup=railslogSQL
  syn match   railslogSQL         '\u.*$' contained
  " Destroy generates multiline SQL, ugh
  syn match   railslogSQL         '^ \%(FROM\|WHERE\|ON\|AND\|OR\|ORDER\) .*$'
  syn match   railslogNumber      '\<\d\+\>%'
  syn match   railslogNumber      '[ (]\@<=\<\d\+\.\d\+\>'
  syn region  railslogString      start='"' skip='\\"' end='"' oneline contained
  syn region  railslogHash        start='{' end='}' oneline contains=railslogHash,railslogString
  syn match   railslogIP          '\<\d\{1,3\}\%(\.\d\{1,3}\)\{3\}\>'
  syn match   railslogTimestamp   '\<\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\>'
  syn match   railslogSessionID   '\<\x\{32\}\>'
  syn match   railslogIdentifier  '^\s*\%(Session ID\|Parameters\)\ze:'
  syn match   railslogSuccess     '\<2\d\d \u[A-Za-z0-9 ]*\>'
  syn match   railslogRedirect    '\<3\d\d \u[A-Za-z0-9 ]*\>'
  syn match   railslogError       '\<[45]\d\d \u[A-Za-z0-9 ]*\>'
  syn match   railslogError       '^DEPRECATION WARNING\>'
  syn keyword railslogHTTP        OPTIONS GET HEAD POST PUT DELETE TRACE CONNECT
  syn region  railslogStackTrace  start=":\d\+:in `\w\+'$" end="^\s*$" keepend fold
  hi def link railslogComment     Comment
  hi def link railslogRender      Keyword
  hi def link railslogModel       Type
  hi def link railslogSQL         PreProc
  hi def link railslogNumber      Number
  hi def link railslogString      String
  hi def link railslogSessionID   Constant
  hi def link railslogIdentifier  Identifier
  hi def link railslogRedirect    railslogSuccess
  hi def link railslogSuccess     Special
  hi def link railslogError       Error
  hi def link railslogHTTP        Special
endfunction

" }}}1
" Statusline {{{1

" Depends: nothing!
" Provides: s:BufInitStatusline

function! s:addtostatus(letter,status)
  let status = a:status
  if status !~ 'Rails' && g:rails_statusline
    let   status=substitute(status,'\C%'.tolower(a:letter),'%'.tolower(a:letter).'%{RailsStatusline()}','')
    if status !~ 'Rails'
      let status=substitute(status,'\C%'.toupper(a:letter),'%'.toupper(a:letter).'%{RailsSTATUSLINE()}','')
    endif
  endif
  return status
endfunction

function! s:BufInitStatusline()
  if g:rails_statusline
    if &l:statusline == ''
      let &l:statusline = &g:statusline
    endif
    if &l:statusline == ''
      let &l:statusline='%<%f %h%m%r%='
      if &ruler
        let &l:statusline = &l:statusline . '%-16( %l,%c-%v %)%P'
      endif
    endif
    let &l:statusline = s:InjectIntoStatusline(&l:statusline)
  endif
endfunction

function! s:InitStatusline()
  if g:rails_statusline
    if &g:statusline == ''
      let &g:statusline='%<%f %h%m%r%='
      if &ruler
        let &g:statusline = &g:statusline . '%-16( %l,%c-%v %)%P'
      endif
    endif
    let &g:statusline = s:InjectIntoStatusline(&g:statusline)
  endif
endfunction

function! s:InjectIntoStatusline(status)
  let status = a:status
  if status !~ 'Rails'
    let status = s:addtostatus('y',status)
    let status = s:addtostatus('r',status)
    let status = s:addtostatus('m',status)
    let status = s:addtostatus('w',status)
    let status = s:addtostatus('h',status)
    if status !~ 'Rails'
      let status=substitute(status,'%=','%{RailsStatusline()}%=','')
    endif
    if status !~ 'Rails' && status != ''
      let status=status.'%{RailsStatusline()}'
    endif
  endif
  return status
endfunction

function! RailsStatusline()
  if exists("b:rails_root")
    let t = RailsFileType()
    if t != ""
      return "[Rails-".t."]"
    else
      return "[Rails]"
    endif
  else
    return ""
  endif
endfunction

function! RailsSTATUSLINE()
  if exists("b:rails_root")
    let t = RailsFileType()
    if t != ""
      return ",RAILS-".toupper(t)
    else
      return ",RAILS"
    endif
  else
    return ""
  endif
endfunction

" }}}1
" Mappings {{{1

" Depends: nothing!
" Exports: s:BufMappings

function! s:BufMappings()
  map <buffer> <silent> <Plug>RailsAlternate  :A<CR>
  map <buffer> <silent> <Plug>RailsRelated    :R<CR>
  map <buffer> <silent> <Plug>RailsFind       :REfind<CR>
  map <buffer> <silent> <Plug>RailsSplitFind  :RSfind<CR>
  map <buffer> <silent> <Plug>RailsVSplitFind :RVfind<CR>
  map <buffer> <silent> <Plug>RailsTabFind    :RTfind<CR>
  if g:rails_mappings
    if !hasmapto("<Plug>RailsFind")
      nmap <buffer> gf              <Plug>RailsFind
    endif
    if !hasmapto("<Plug>RailsSplitFind")
      nmap <buffer> <C-W>f          <Plug>RailsSplitFind
    endif
    if !hasmapto("<Plug>RailsTabFind")
      nmap <buffer> <C-W>gf         <Plug>RailsTabFind
    endif
    if !hasmapto("<Plug>RailsAlternate")
      nmap <buffer> [f              <Plug>RailsAlternate
    endif
    if !hasmapto("<Plug>RailsRelated")
      nmap <buffer> ]f              <Plug>RailsRelated
    endif
    if exists("$CREAM")
      imap <buffer> <C-CR> <C-O><Plug>RailsFind
      " Are these a good idea?
      imap <buffer> <M-[>  <C-O><Plug>RailsAlternate
      imap <buffer> <M-]>  <C-O><Plug>RailsRelated
    endif
  endif
  " SelectBuf you're a dirty hack
  let v:errmsg = ""
endfunction

" }}}1
" Project {{{

" Depends: s:gsub, s:escarg, s:warn, s:sub, s:relglob

function! s:Project(bang,arg)
  let rr = RailsRoot()
  exe "Project ".a:arg
  let line = search('^[^ =]*="'.s:gsub(rr,'[\/]','[\\/]').'"')
  let projname = s:gsub(fnamemodify(rr,':t'),'\=','-') " .'_on_rails'
  if line && a:bang
    let projname = matchstr(getline('.'),'^[^=]*')
    " Most of this would be unnecessary if the project.vim author had just put
    " the newlines AFTER each project rather than before.  Ugh.
    norm zR0"_d%
    if line('.') > 2
      delete _
    endif
    if line('.') != line('$')
      .-2
    endif
    let line = 0
  elseif !line
    $
  endif
  if !line
    if line('.') > 1
      append

.
    endif
    let line = line('.')+1
    call s:NewProject(projname,rr,a:bang)
  endif
  normal! zMzo
  if search("^ app=app {","W",line+10)
    normal! zo
    exe line
  endif
  normal! 0zt
endfunction

function! s:NewProject(proj,rr,fancy)
    let line = line('.')+1
    let template = s:NewProjectTemplate(a:proj,a:rr,a:fancy)
    silent put =template
    exe line
    " Ugh. how else can I force detecting folds?
    setlocal foldmethod=manual
    norm! $%
    silent exe "doautocmd User ".s:escarg(a:rr)."/Rproject"
    let newline = line('.')
    exe line
    norm! $%
    if line('.') != newline
      call s:warn("Warning: Rproject autocommand failed to leave cursor at end of project")
    endif
    exe line
    setlocal foldmethod=marker
    setlocal nomodified
    " FIXME: make undo stop here
    if !exists("g:maplocalleader")
      silent! normal \R
    else " Needs to be tested
      exe 'silent! normal '.g:maplocalleader.'R'
    endif
endfunction

function! s:NewProjectTemplate(proj,rr,fancy)
  let str = a:proj.'="'.a:rr."\" CD=. filter=\"*\" {\n"
  let str = str." app=app {\n"
  if isdirectory(a:rr.'/app/apis')
    let str = str."  apis=apis {\n  }\n"
  endif
  let str = str."  controllers=controllers filter=\"**\" {\n  }\n"
  let str = str."  helpers=helpers filter=\"**\" {\n  }\n"
  let str = str."  models=models filter=\"**\" {\n  }\n"
  if a:fancy
    let str = str."  views=views {\n"
    let views = s:relglob(a:rr.'/app/views/','*')."\n"
    while views != ''
      let dir = matchstr(views,'^.\{-\}\ze\n')
      let views = s:sub(views,'^.{-}\n','')
      let str = str."   ".dir."=".dir.' filter="**" {'."\n   }\n"
    endwhile
    let str = str."  }\n"
  else
    let str = str."  views=views filter=\"**\" {\n  }\n"
  endif
  let str = str . " }\n"
  let str = str . " config=config {\n  environments=environments {\n  }\n }\n"
  let str = str . " db=db {\n"
  if isdirectory(a:rr.'/db/migrate')
    let str = str . "  migrate=migrate {\n  }\n"
  endif
  let str = str . " }\n"
  let str = str . " lib=lib filter=\"* */**/*.rb \" {\n  tasks=tasks filter=\"**/*.rake\" {\n  }\n }\n"
  let str = str . " public=public {\n  images=images {\n  }\n  javascripts=javascripts {\n  }\n  stylesheets=stylesheets {\n  }\n }\n"
  if isdirectory(a:rr.'/spec')
    let str = str . " spec=spec {\n"
    let str = str . "  controllers=controllers filter=\"**\" {\n  }\n"
    let str = str . "  fixtures=fixtures filter=\"**\" {\n  }\n"
    let str = str . "  helpers=helpers filter=\"**\" {\n  }\n"
    let str = str . "  models=models filter=\"**\" {\n  }\n"
    let str = str . "  views=views filter=\"**\" {\n  }\n }\n"
  endif
  let str = str . " test=test {\n"
  if isdirectory(a:rr.'/test/fixtures')
    let str = str . "  fixtures=fixtures filter=\"**\" {\n  }\n"
  endif
  if isdirectory(a:rr.'/test/functional')
    let str = str . "  functional=functional filter=\"**\" {\n  }\n"
  endif
  if isdirectory(a:rr.'/test/integration')
    let str = str . "  integration=integration filter=\"**\" {\n  }\n"
  endif
  if isdirectory(a:rr.'/test/mocks')
    let str = str . "  mocks=mocks filter=\"**\" {\n  }\n"
  endif
  if isdirectory(a:rr.'/test/unit')
    let str = str . "  unit=unit filter=\"**\" {\n  }\n"
  endif
  let str = str . " }\n}\n"
  return str
endfunction

" }}}1
" Database {{{1

" Depends: s:environment, s:rubyeval, s:rv, reloadability

function! s:extractdbvar(str,arg)
  return matchstr("\n".a:str."\n",'\n'.a:arg.'=\zs.\{-\}\ze\n')
endfunction

function! s:BufDatabase(...)
  if exists("s:lock_database")
    return
  endif
  let s:lock_database = 1
  let rv = s:rv()
  if (a:0 && a:1 > 1)
    unlet! s:dbext_type_{rv}
  endif
  if (a:0 > 1 && a:2 != '')
    let env = a:2
  else
    let env = s:environment()
  endif
  " Crude caching mechanism
  if !exists("s:dbext_type_".rv)
    if exists("g:loaded_dbext") && (g:rails_dbext + (a:0 ? a:1 : 0)) > 0 && filereadable(RailsRoot()."/config/database.yml")
      " Ideally we would filter this through ERB but that could be insecure.
      " It might be possible to make use of taint checking.
      let out = ""
      if has("ruby")
        ruby require 'yaml'; VIM::command('let out = %s' % File.open(VIM::evaluate("RailsRoot()")+"/config/database.yml") {|f| y = YAML::load(f); e = y[VIM::evaluate("env")]; i=0; e=y[e] while e.respond_to?(:to_str) && (i+=1)<16; e.map {|k,v| "#{k}=#{v}\n" if v}.compact.join }.inspect) rescue nil
      endif
      if out == ""
        let cmdb = 'require %{yaml}; File.open(%q{'.RailsRoot().'/config/database.yml}) {|f| y = YAML::load(f); e = y[%{'
        let cmde = '}]; i=0; e=y[e] while e.respond_to?(:to_str) && (i+=1)<16; e.each{|k,v|puts k.to_s+%{=}+v.to_s}}'
        if a:0 ? a:1 : g:rails_expensive
          let out = s:rubyeval(cmdb.env.cmde,'')
        else
          unlet! s:lock_database
          return
        endif
      endif
      let adapter = s:extractdbvar(out,'adapter')
      let s:dbext_bin_{rv} = ''
      let s:dbext_integratedlogin_{rv} = ''
      if adapter == 'postgresql'
        let adapter = 'pgsql'
      elseif adapter == 'sqlite3'
        let adapter = 'sqlite'
        " Does not appear to work
        let s:dbext_bin = 'sqlite3'
      elseif adapter == 'sqlserver'
        let adapter = 'sqlsrv'
      elseif adapter == 'sybase'
        let adapter = 'asa'
      elseif adapter == 'oci'
        let adapter = 'ora'
      endif
      let s:dbext_type_{rv} = toupper(adapter)
      let s:dbext_user_{rv} = s:extractdbvar(out,'username')
      let s:dbext_passwd_{rv} = s:extractdbvar(out,'password')
      if s:dbext_passwd_{rv} == '' && adapter == 'mysql'
        " Hack to override password from .my.cnf
        let s:dbext_extra_{rv} = ' --password='
      else
        let s:dbext_extra_{rv} = ''
      endif
      let s:dbext_dbname_{rv} = s:extractdbvar(out,'database')
      if s:dbext_dbname_{rv} != '' && s:dbext_dbname_{rv} !~ '^:' && adapter =~? '^sqlite'
        let s:dbext_dbname_{rv} = RailsRoot().'/'.s:dbext_dbname_{rv}
      endif
      let s:dbext_profile_{rv} = ''
      let s:dbext_host_{rv} = s:extractdbvar(out,'host')
      let s:dbext_port_{rv} = s:extractdbvar(out,'port')
      let s:dbext_dsnname_{rv} = s:extractdbvar(out,'dsn')
      if s:dbext_host_{rv} =~? '^\cDBI:'
        if s:dbext_host_{rv} =~? '\c\<Trusted[_ ]Connection\s*=\s*yes\>'
          let s:dbext_integratedlogin_{rv} = 1
        endif
        let s:dbext_host_{rv} = matchstr(s:dbext_host_{rv},'\c\<\%(Server\|Data Source\)\s*=\s*\zs[^;]*')
      endif
    endif
  endif
  if exists("s:dbext_type_".rv)
    silent! let b:dbext_type    = s:dbext_type_{rv}
    silent! let b:dbext_profile = s:dbext_profile_{rv}
    silent! let b:dbext_bin     = s:dbext_bin_{rv}
    silent! let b:dbext_user    = s:dbext_user_{rv}
    silent! let b:dbext_passwd  = s:dbext_passwd_{rv}
    silent! let b:dbext_dbname  = s:dbext_dbname_{rv}
    silent! let b:dbext_host    = s:dbext_host_{rv}
    silent! let b:dbext_port    = s:dbext_port_{rv}
    silent! let b:dbext_dsnname = s:dbext_dsnname_{rv}
    silent! let b:dbext_extra   = s:dbext_extra_{rv}
    silent! let b:dbext_integratedlogin = s:dbext_integratedlogin_{rv}
    if b:dbext_type == 'PGSQL'
      let $PGPASSWORD = b:dbext_passwd
    elseif exists('$PGPASSWORD')
      let $PGPASSWORD = ''
    endif
  endif
  if a:0 >= 3 && a:3 && exists(":Create")
    if exists("b:dbext_dbname") && exists("b:dbext_type") && b:dbext_type !~? 'sqlite'
      let db = b:dbext_dbname
      if b:dbext_type == 'PGSQL'
        " I don't always have a default database for a user so using the
        " default user's database is a better choice for my setup.  It
        " probably won't work for everyone but nothing will.
        let b:dbext_dbname = 'postgres'
      else
        let b:dbext_dbname = ''
      endif
      exe "Create database ".db
      let b:dbext_dbname = db
    endif
  endif
  unlet! s:lock_database
endfunction

" }}}1
" Abbreviations {{{1

" Depends: s:sub, s:gsub, s:string, s:linepeak, s:error

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

function! s:TheMagicC()
  let l = s:linepeak()
  if l =~ '\<find\s*\((\|:first,\|:all,\)' || l =~ '\<paginate\>'
    return s:selectiveexpand('..',':conditions => ',':c')
  elseif l =~ '\<render\s*(\=\s*:partial\s\*=>\s*'
    return s:selectiveexpand('..',':collection => ',':c')
  elseif RailsFileType() =~ '^model\>'
    return s:selectiveexpand('..',':conditions => ',':c')
  else
    return s:selectiveexpand('..',':controller => ',':c')
  endif
endfunction

function! s:AddSelectiveExpand(abbr,pat,expn,...)
  let expn  = s:gsub(s:gsub(a:expn        ,'[\"|]','\\&'),'\<','\\<Lt>')
  let expn2 = s:gsub(s:gsub(a:0 ? a:1 : '','[\"|]','\\&'),'\<','\\<Lt>')
  if a:0
    exe "inoreabbrev <buffer> <silent> ".a:abbr." <C-R>=<SID>selectiveexpand(".s:string(a:pat).",\"".expn."\",".s:string(a:abbr).",\"".expn2."\")<CR>"
  else
    exe "inoreabbrev <buffer> <silent> ".a:abbr." <C-R>=<SID>selectiveexpand(".s:string(a:pat).",\"".expn."\",".s:string(a:abbr).")<CR>"
  endif
endfunction

function! s:AddTabExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'..',a:expn)
endfunction

function! s:AddBracketExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'[[.]',a:expn)
endfunction

function! s:AddColonExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,':',a:expn)
endfunction

function! s:AddParenExpand(abbr,expn,...)
  if a:0
    call s:AddSelectiveExpand(a:abbr,'(',a:expn,a:1)
  else
    call s:AddSelectiveExpand(a:abbr,'(',a:expn,'')
  endif
endfunction

function! s:BufAbbreviations()
  command! -buffer -bar -nargs=* -bang Rabbrev :call s:Abbrev(<bang>0,<f-args>)
  " Some of these were cherry picked from the TextMate snippets
  if g:rails_abbreviations
    let t = RailsFileType()
    " Limit to the right filetypes.  But error on the liberal side
    if t =~ '^\(controller\|view\|helper\|test-functional\|test-integration\)\>'
      Rabbrev pa[ params
      Rabbrev rq[ request
      Rabbrev rs[ response
      Rabbrev se[ session
      Rabbrev hd[ headers
      Rabbrev co[ cookies
      Rabbrev fl[ flash
      Rabbrev rr( render
      Rabbrev ra( render :action\ =>\ 
      Rabbrev rc( render :controller\ =>\ 
      Rabbrev rf( render :file\ =>\ 
      Rabbrev ri( render :inline\ =>\ 
      Rabbrev rj( render :json\ =>\ 
      Rabbrev rl( render :layout\ =>\ 
      Rabbrev rp( render :partial\ =>\ 
      Rabbrev rt( render :text\ =>\ 
      Rabbrev rx( render :xml\ =>\ 
    endif
    if t =~ '^\%(view\|helper\)\>'
      Rabbrev dotiw distance_of_time_in_words
      Rabbrev taiw  time_ago_in_words
    endif
    if t =~ '^controller\>'
      "call s:AddSelectiveExpand('rn','[,\r]','render :nothing => true')
      "let b:rails_abbreviations = b:rails_abbreviations . "rn\trender :nothing => true\n"
      Rabbrev re(  redirect_to
      Rabbrev rea( redirect_to :action\ =>\ 
      Rabbrev rec( redirect_to :controller\ =>\ 
      Rabbrev rst( respond_to
    endif
    if t =~ '^model-arb\>' || t =~ '^model$'
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
    endif
    if t =~ '^\%(db-\)\=\%(migration\|schema\)\>'
      Rabbrev mac(  add_column
      Rabbrev mrnc( rename_column
      Rabbrev mrc(  remove_column
      Rabbrev mct( create_table
      "Rabbrev mct   create_table\ :\ do\ <Bar>t<Bar><CR>end<Esc>k$6hi
      Rabbrev mrnt( rename_table
      Rabbrev mdt(  drop_table
      Rabbrev mcc(  t.column
    endif
    if t =~ '^test\>'
      "Rabbrev ae(   assert_equal
      Rabbrev ase(  assert_equal
      "Rabbrev ako(  assert_kind_of
      Rabbrev asko( assert_kind_of
      "Rabbrev ann(  assert_not_nil
      Rabbrev asnn( assert_not_nil
      "Rabbrev ar(   assert_raise
      Rabbrev asr(  assert_raise
      "Rabbrev are(  assert_response
      Rabbrev asre( assert_response
      Rabbrev art(  assert_redirected_to
    endif
    Rabbrev :a    :action\ =>\ 
    inoreabbrev <buffer> <silent> :c <C-R>=<SID>TheMagicC()<CR>
    " Lie a little
    if t =~ '^view\>'
      let b:rails_abbreviations = b:rails_abbreviations . ":c\t:collection => \n"
    elseif s:controller() != ''
      let b:rails_abbreviations = b:rails_abbreviations . ":c\t:controller => \n"
    else
      let b:rails_abbreviations = b:rails_abbreviations . ":c\t:conditions => \n"
    endif
    Rabbrev :i    :id\ =>\ 
    Rabbrev :o    :object\ =>\ 
    Rabbrev :p    :partial\ =>\ 
    Rabbrev logd( logger.debug
    Rabbrev logi( logger.info
    Rabbrev logw( logger.warn
    Rabbrev loge( logger.error
    Rabbrev logf( logger.fatal
    Rabbrev fi(   find
    Rabbrev AR::  ActiveRecord
    Rabbrev AV::  ActionView
    Rabbrev AC::  ActionController
    Rabbrev AS::  ActiveSupport
    Rabbrev AM::  ActionMailer
    Rabbrev AE::  ActiveResource
    Rabbrev AWS:: ActionWebService
  endif
endfunction

function! s:Abbrev(bang,...) abort
  if !exists("b:rails_abbreviations")
    let b:rails_abbreviations = "\n"
  endif
  if a:0 > 3 || (a:bang && (a:0 != 1))
    return s:error("Rabbrev: invalid arguments")
  endif
  if a:bang
    return s:unabbrev(a:1)
  endif
  if a:0 == 0
    echo s:sub(b:rails_abbreviations,'^\n','')
    return
  endif
  let lhs = a:1
  if a:0 > 3 || a:0 < 2
    return s:error("Rabbrev: invalid arguments")
  endif
  let rhs = a:2
  call s:unabbrev(lhs,1)
  if lhs =~ '($'
    let b:rails_abbreviations = b:rails_abbreviations . lhs . "\t" . rhs . "" . (a:0 > 2 ? "\t".a:3 : ""). "\n"
    let llhs = s:sub(lhs,'\($','')
    if a:0 > 2
      call s:AddParenExpand(llhs,rhs,a:3)
    else
      call s:AddParenExpand(llhs,rhs)
    endif
    return
  endif
  if a:0 > 2
    return s:error("Rabbrev: invalid arguments")
  endif
  if lhs =~ ':$'
    let llhs = s:sub(lhs,':=:$','')
    call s:AddColonExpand(llhs,rhs)
  elseif lhs =~ '\[$'
    let llhs = s:sub(lhs,'\[$','')
    call s:AddBracketExpand(llhs,rhs)
  elseif lhs =~ '\w$'
    call s:AddTabExpand(lhs,rhs)
  else
    return s:error("Rabbrev: unimplemented")
  endif
  let b:rails_abbreviations = b:rails_abbreviations . lhs . "\t" . rhs . "\n"
endfunction

function! s:unabbrev(abbr,...)
  let abbr = s:sub(a:abbr,'%(::|\(|\[)$','')
  let pat  = s:sub(abbr,'\\','\\\\')
  if !exists("b:rails_abbreviations")
    let b:rails_abbreviations = "\n"
  endif
  let b:rails_abbreviations = substitute(b:rails_abbreviations,'\V\C\n'.pat.'\(\t\|::\t\|(\t\|[\t\)\.\{-\}\n','\n','')
  if a:0 == 0 || a:1 == 0
    exe "iunabbrev <buffer> ".abbr
  endif
endfunction

" }}}1
" Settings {{{1

" Depends: s:error, s:sub, s:sname, s:escvar, s:lastmethod, s:environment, s:gsub, s:lastmethodlib, s:gsub

function! s:Set(bang,...)
  let c = 1
  let defscope = ''
  while c <= a:0
    let arg = a:{c}
    let c = c + 1
    if arg =~? '^<[abgl]\=>$'
      let defscope = (matchstr(arg,'<\zs.*\ze>'))
    elseif arg !~ '='
      if defscope != '' && arg !~ '^\w:'
        let arg = defscope.':'.opt
      endif
      let val = s:getopt(arg)
      if val == '' && s:opts() !~ '\<'.arg.'\n'
        call s:error("No such rails.vim option: ".arg)
      else
        echo arg."=".val
      endif
    else
      let opt = matchstr(arg,'[^=]*')
      let val = s:sub(arg,'^[^=]*\=','')
      if defscope != '' && opt !~ '^\w:'
        let opt = defscope.':'.opt
      endif
      call s:setopt(opt,val)
    endif
  endwhile
endfunction

function! s:getopt(opt,...)
  let opt = a:opt
  if a:0
    let scope = a:1
  elseif opt =~ '^[abgl]:'
    let scope = tolower(matchstr(opt,'^\w'))
    let opt = s:sub(opt,'^\w:','')
  else
    let scope = 'abgl'
  endif
  if scope =~ 'l' && &filetype != 'ruby'
    let scope = s:sub(scope,'l','b')
  endif
  if scope =~ 'l'
    call s:LocalModelines()
  endif
  let opt = s:sub(opt,'<%(rake|rake_task|rake_target)$','task')
  " Get buffer option
  if scope =~ 'l' && exists("b:_".s:sname()."_".s:escvar(s:lastmethod())."_".opt)
    return b:_{s:sname()}_{s:escvar(s:lastmethod())}_{opt}
  elseif exists("b:".s:sname()."_".opt) && (scope =~ 'b' || (scope =~ 'l' && s:lastmethod() == ''))
    return b:{s:sname()}_{opt}
  elseif scope =~ 'a' && exists("s:_".s:rv()."_".s:environment()."_".opt)
    return s:_{s:rv()}_{s:environment()}_{opt}
  elseif scope =~ 'g' && exists("g:".s:sname()."_".opt)
    return g:{s:sname()}_{opt}
  else
    return ""
  endif
endfunction

function! s:setopt(opt,val)
  if a:opt =~? '[abgl]:'
    let scope = matchstr(a:opt,'^\w')
    let opt = s:sub(a:opt,'^\w:','')
  else
    let scope = ''
    let opt = a:opt
  endif
  let opt = s:sub(opt,'<%(rake|rake_task|rake_target)$','task')
  let defscope = matchstr(s:opts(),'\n\zs\w\ze:'.opt,'\n')
  if defscope == ''
    let defscope = 'a'
  endif
  if scope == ''
    let scope = defscope
  endif
  if &filetype == 'ruby' && (scope == 'B' || scope == 'l')
    let scope = 'b'
  endif
  if opt =~ '\W'
    return s:error("Invalid option ".a:opt)
  elseif scope =~? 'a'
    let s:_{s:rv()}_{s:environment()}_{opt} = a:val
  elseif scope == 'B' && defscope == 'l'
    let b:_{s:sname()}_{s:escvar('')}_{opt} = a:val
  elseif scope =~? 'b'
    let b:{s:sname()}_{opt} = a:val
  elseif scope =~? 'g'
    let g:{s:sname()}_{opt} = a:val
  elseif scope =~? 'l'
    let b:_{s:sname()}_{s:escvar(s:lastmethod())}_{opt} = a:val
  else
    return s:error("Invalid scope for ".a:opt)
  endif
endfunction

function! s:opts()
  return "\nb:alternate\nb:controller\na:gnu_screen\nb:model\nl:preview\nb:task\nl:related\na:root_url\na:ruby_fork_port\n"
endfunction

function! s:SetComplete(A,L,P)
  if a:A =~ '='
    let opt = matchstr(a:A,'[^=]*')
    return opt."=".s:getopt(opt)
  else
    let extra = matchstr(a:A,'^[abgl]:')
    let opts = s:gsub(s:sub(s:gsub(s:opts(),'\n\w:','\n'.extra),'^\n',''),'\n','=\n')
    return opts
  endif
  return ""
endfunction

function! s:BufModelines()
  if !g:rails_modelines
    return
  endif
  let lines = getline("$")."\n".getline(line("$")-1)."\n".getline(1)."\n".getline(2)."\n".getline(3)."\n"
  let pat = '\s\+\zs.\{-\}\ze\%(\n\|\s\s\|#{\@!\|%>\|-->\|$\)'
  let cnt = 1
  let mat    = matchstr(lines,'\C\<Rset'.pat)
  let matend = matchend(lines,'\C\<Rset'.pat)
  while mat != "" && cnt < 10
    let mat = s:sub(mat,'\s+$','')
    let mat = s:gsub(mat,'\|','\\|')
    if mat != ''
      silent! exe "Rset <B> ".mat
    endif
    let mat    = matchstr(lines,'\C\<Rset'.pat,matend)
    let matend = matchend(lines,'\C\<Rset'.pat,matend)
    let cnt = cnt + 1
  endwhile
endfunction

function! s:LocalModelines()
  if !g:rails_modelines
    return
  endif
  let lbeg = s:lastmethodline()
  let lend = s:endof(lbeg)
  if lbeg == 0 || lend == 0
    return
  endif
  let lines = "\n"
  let lnum = lbeg
  while lnum < lend && lnum < lbeg + 5
    let lines = lines . getline(lnum) . "\n"
    let lnum = lnum + 1
  endwhile
  let pat = '\s\+\zs.\{-\}\ze\%(\n\|\s\s\|#{\@!\|%>\|-->\|$\)'
  let cnt = 1
  let mat    = matchstr(lines,'\C\<rset'.pat)
  let matend = matchend(lines,'\C\<rset'.pat)
  while mat != "" && cnt < 10
    let mat = s:sub(mat,'\s+$','')
    let mat = s:gsub(mat,'\|','\\|')
    if mat != ''
      silent! exe "Rset <l> ".mat
    endif
    let mat    = matchstr(lines,'\C\<rset'.pat,matend)
    let matend = matchend(lines,'\C\<rset'.pat,matend)
    let cnt = cnt + 1
  endwhile
endfunction

" }}}1
" Detection {{{1

function! s:callback(file)
  if RailsRoot() != ""
    let var = "callback_".s:rv()."_".s:escvar(a:file)
    if !exists("s:".var) || exists("b:rails_refresh")
      let s:{var} = s:hasfile(a:file)
    endif
    if s:{var}
      if exists(":sandbox")
        sandbox source `=RailsRoot().'/'.a:file`
      elseif g:rails_modelines
        source `=RailsRoot().'/'.a:file`
      endif
    endif
  endif
endfunction

function! RailsBufInit(path)
  let cpo_save = &cpo
  set cpo&vim
  let firsttime = !(exists("b:rails_root") && b:rails_root == a:path)
  let b:rails_root = a:path
  " Apparently RailsFileType() can be slow if the underlying file system is
  " slow (even though it doesn't really do anything IO related).  This caching
  " is a temporary hack; if it doesn't cause problems it should probably be
  " refactored.
  unlet! b:rails_cached_file_type
  let b:rails_cached_file_type = RailsFileType()
  if g:rails_history_size > 0
    if !exists("g:RAILS_HISTORY")
      let g:RAILS_HISTORY = ""
    endif
    let path = a:path
    let g:RAILS_HISTORY = s:scrub(g:RAILS_HISTORY,path)
    if has("win32")
      let g:RAILS_HISTORY = s:scrub(g:RAILS_HISTORY,s:gsub(path,'\\','/'))
    endif
    let path = fnamemodify(path,':p:~:h')
    let g:RAILS_HISTORY = s:scrub(g:RAILS_HISTORY,path)
    if has("win32")
      let g:RAILS_HISTORY = s:scrub(g:RAILS_HISTORY,s:gsub(path,'\\','/'))
    endif
    let g:RAILS_HISTORY = path."\n".g:RAILS_HISTORY
    let g:RAILS_HISTORY = s:sub(g:RAILS_HISTORY,'%(.{-}\n){,'.g:rails_history_size.'}\zs.*','')
  endif
  call s:callback("config/syntax.vim")
  if &ft == "mason"
    setlocal filetype=eruby
  elseif &ft =~ '^\%(conf\|ruby\)\=$' && expand("%:e") =~ '^\%(rjs\|rxml\|builder\|rake\|mab\)$'
    setlocal filetype=ruby
  elseif &ft =~ '^\%(conf\|ruby\)\=$' && expand("%:t") =~ '^\%(Rake\|Cap\)file$'
    setlocal filetype=ruby
  elseif &ft =~ '^\%(liquid\)\=$' && expand("%:e") == "liquid"
    setlocal filetype=liquid
  elseif &ft =~ '^\%(haml\|x\=html\)\=$' && expand("%:e") == "haml"
    setlocal filetype=haml
  elseif &ft =~ '^\%(sass\|conf\)\=$' && expand("%:e") == "sass"
    setlocal filetype=sass
  elseif &ft =~ '^\%(dryml\)\=$' && expand("%:e") == "dryml"
    setlocal filetype=dryml
  elseif (&ft == "" || v:version < 701) && expand("%:e") =~ '^\%(rhtml\|erb\)$'
    setlocal filetype=eruby
  elseif (&ft == "" || v:version < 700) && expand("%:e") == 'yml'
    setlocal filetype=yaml
  elseif firsttime
    " Activate custom syntax
    let &syntax = &syntax
  endif
  if firsttime
    call s:BufInitStatusline()
  endif
  if expand("%:e") == "log"
    setlocal modifiable filetype=railslog
    silent! %s/\%(\e\[[0-9;]*m\|\r$\)//g
    setlocal readonly nomodifiable noswapfile autoread foldmethod=syntax
    nnoremap <buffer> <silent> R :checktime<CR>
    nnoremap <buffer> <silent> G :checktime<Bar>$<CR>
    nnoremap <buffer> <silent> q :bwipe<CR>
    $
  endif
  call s:BufSettings()
  call s:BufCommands()
  call s:BufAbbreviations()
  call s:BufDatabase()
  " snippetsEmu.vim
  if exists('g:loaded_snippet')
    silent! runtime! ftplugin/rails_snippets.vim
    " filetype snippets need to come last for higher priority
    exe "silent! runtime! ftplugin/".&filetype."_snippets.vim"
  endif
  let t = RailsFileType()
  let t = "-".t
  let f = '/'.RailsFilePath()
  if f =~ '[ !#$%\,]'
    let f = ''
  endif
  runtime! macros/rails.vim
  silent doautocmd User Rails
  if t != '-'
    exe "silent doautocmd User Rails".s:gsub(t,'-','.')
  endif
  if f != ''
    exe "silent doautocmd User Rails".f
  endif
  call s:callback("config/rails.vim")
  call s:BufModelines()
  call s:BufMappings()
  "unlet! b:rails_cached_file_type
  let &cpo = cpo_save
  return b:rails_root
endfunction

function! s:SetBasePath()
  let rp = s:gsub(RailsRoot(),'[ ,]','\\&')
  let t = RailsFileType()
  let oldpath = s:sub(&l:path,'^\.,','')
  if stridx(oldpath,rp) == 2
    let oldpath = ''
  endif
  let &l:path = '.,'.rp.",".rp."/app/controllers,".rp."/app,".rp."/app/models,".rp."/app/helpers,".rp."/config,".rp."/lib,".rp."/vendor,".rp."/vendor/plugins/*/lib,".rp."/test/unit,".rp."/test/functional,".rp."/test/integration,".rp."/app/apis,".rp."/app/services,".rp."/test,"."/vendor/plugins/*/test,".rp."/vendor/rails/*/lib,".rp."/vendor/rails/*/test,".rp."/spec,".rp."/spec/*,"
  if s:controller() != ''
    let &l:path = &l:path . rp . '/app/views/' . s:controller() . ',' . rp . '/app/views,' . rp . '/public,'
  endif
  if t =~ '^log\>'
    let &l:path = &l:path . rp . '/app/views,'
  endif
  if &l:path =~ '://'
    let &l:path = ".,"
  endif
  let &l:path = &l:path . oldpath
endfunction

function! s:BufSettings()
  if !exists('b:rails_root')
    return ''
  endif
  call s:SetBasePath()
  let rp = s:gsub(RailsRoot(),'[ ,]','\\&')
  let &l:errorformat = s:efm
  setlocal makeprg=rake
  if stridx(&tags,rp) == -1
    let &l:tags = &tags . "," . rp . "/tags," . rp . "/.tags"
  endif
  if has("gui_win32") || has("gui_running")
    let code      = '*.rb;*.rake;Rakefile'
    let templates = '*.'.s:gsub(s:view_types,',',';*.')
    let fixtures  = '*.yml;*.csv'
    let statics   = '*.html;*.css;*.js;*.xml;*.xsd;*.sql;.htaccess;README;README_FOR_APP'
    let b:browsefilter = ""
          \."All Rails Files\t".code.';'.templates.';'.fixtures.';'.statics."\n"
          \."Source Code (*.rb, *.rake)\t".code."\n"
          \."Templates (*.rhtml, *.rxml, *.rjs)\t".templates."\n"
          \."Fixtures (*.yml, *.csv)\t".fixtures."\n"
          \."Static Files (*.html, *.css, *.js)\t".statics."\n"
          \."All Files (*.*)\t*.*\n"
  endif
  setlocal includeexpr=RailsIncludeexpr()
  let &l:suffixesadd=".rb,.".s:gsub(s:view_types,',',',.').",.css,.js,.yml,.csv,.rake,.sql,.html,.xml"
  if &ft =~ '^\%(e\=ruby\|[yh]aml\|javascript\|css\|sass\)$'
    setlocal sw=2 sts=2 et
    "set include=\\<\\zsAct\\f*::Base\\ze\\>\\\|^\\s*\\(require\\\|load\\)\\s\\+['\"]\\zs\\f\\+\\ze
    if exists('+completefunc')
      if &completefunc == ''
        set completefunc=syntaxcomplete#Complete
      endif
    endif
  endif
  if &filetype == "ruby"
    let &l:suffixesadd=".rb,.".s:gsub(s:view_types,',',',.').",.yml,.csv,.rake,s.rb"
    if expand('%:e') == 'rake'
      setlocal define=^\\s*def\\s\\+\\(self\\.\\)\\=\\\|^\\s*\\%(task\\\|file\\)\\s\\+[:'\"]
    else
      setlocal define=^\\s*def\\s\\+\\(self\\.\\)\\=
    endif
    " This really belongs in after/ftplugin/ruby.vim but we'll be nice
    if exists("g:loaded_surround") && !exists("b:surround_101")
      let b:surround_5   = "\r\nend"
      let b:surround_69  = "\1expr: \1\rend"
      let b:surround_101 = "\r\nend"
    endif
  elseif &filetype == 'yaml' || expand('%:e') == 'yml'
    setlocal define=^\\%(\\h\\k*:\\)\\@=
    let &l:suffixesadd=".yml,.csv,.rb,.".s:gsub(s:view_types,',',',.').",.rake,s.rb"
  elseif &filetype == "eruby"
    let &l:suffixesadd=".".s:gsub(s:view_types,',',',.').",.rb,.css,.js,.html,.yml,.csv"
    if exists("g:loaded_allml")
      " allml is available on vim.org.
      let b:allml_stylesheet_link_tag = "<%= stylesheet_link_tag '\r' %>"
      let b:allml_javascript_include_tag = "<%= javascript_include_tag '\r' %>"
      let b:allml_doctype_index = 10
    endif
  endif
  if &filetype == "eruby" || &filetype == "yaml"
    " surround.vim
    if exists("g:loaded_surround")
      " The idea behind the || part here is that one can normally define the
      " surrounding to omit the hyphen (since standard ERuby does not use it)
      " but have it added in Rails ERuby files.  Unfortunately, this makes it
      " difficult if you really don't want a hyphen in Rails ERuby files.  If
      " this is your desire, you will need to accomplish it via a rails.vim
      " autocommand.
      if !exists("b:surround_45") || b:surround_45 == "<% \r %>" " -
        let b:surround_45 = "<% \r -%>"
      endif
      if !exists("b:surround_61") " =
        let b:surround_61 = "<%= \r %>"
      endif
      if !exists("b:surround_35") " #
        let b:surround_35 = "<%# \r %>"
      endif
      if !exists("b:surround_101") || b:surround_101 == "<% \r %>\n<% end %>" "e
        let b:surround_5   = "<% \r -%>\n<% end -%>"
        let b:surround_69  = "<% \1expr: \1 -%>\r<% end -%>"
        let b:surround_101 = "<% \r -%>\n<% end -%>"
      endif
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
  autocmd BufWritePost */config/database.yml unlet! s:dbext_type_{s:rv()} " Force reload
  autocmd BufWritePost */test/test_helper.rb call s:cacheclear("user_asserts")
  autocmd BufWritePost */config/routes.rb    call s:cacheclear("named_routes")
  autocmd FileType * if exists("b:rails_root") | call s:BufSettings() | endif
  autocmd Syntax ruby,eruby,yaml,haml,javascript,railslog if exists("b:rails_root") | call s:BufSyntax() | endif
  silent! autocmd QuickFixCmdPre  make* call s:QuickFixCmdPre()
  silent! autocmd QuickFixCmdPost make* call s:QuickFixCmdPost()
augroup END

" }}}1
" Initialization {{{1

map <SID>xx <SID>xx
let s:sid = s:sub(maparg("<SID>xx"),'xx$','')
unmap <SID>xx
let s:file = expand('<sfile>:p')

" }}}1

let &cpo = s:cpo_save

" vim:set sw=2 sts=2:
