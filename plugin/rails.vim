" rails.vim - Detect a rails application
" Author:       Tim Pope <vimNOSPAM@tpope.info>
" GetLatestVimScripts: 1567 1 :AutoInstall: rails.vim
" URL:          http://svn.tpope.net/rails/vim/railsvim
" $Id$

" See doc/rails.txt for details. Grab it from the URL above if you don't have it
" To access it from Vim, see :help add-local-help (hint: :helptags ~/.vim/doc)
" Afterwards, you should be able to do :help rails

" ============================================================================

" Exit quickly when:
" - this plugin was already loaded (or disabled)
" - when 'compatible' is set
if exists("g:loaded_rails") && (g:loaded_rails && !g:rails_debug) || &cp
  finish
endif
let g:loaded_rails = 1

let cpo_save = &cpo
set cpo&vim

" Utility Functions {{{1

function! s:sub(str,pat,rep)
  return substitute(a:str,'\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep)
  return substitute(a:str,'\C'.a:pat,a:rep,'g')
endfunction

function! s:escpath(p)
  return s:gsub(a:p,'[ ,]','\\&')
endfunction

function! s:escarg(p)
  return s:gsub(a:p,'[ !%#]','\\&')
endfunction

function! s:esccmd(p)
  return s:gsub(a:p,'[!%#]','\\&')
endfunction

function! s:r()
  return RailsRoot()
endfunction

function! s:rp()
  " Rails root, escaped for use in &path
  return s:escpath(s:r())
endfunction

function! s:ra()
  " Rails root, escaped for use as single argument
  return s:escarg(s:r())
endfunction

function! s:rc()
  " Rails root, escaped for use with a command (spaces not escaped)
  return s:esccmd(s:r())
endfunction

function! s:rv()
  " Rails root, escaped to be a variable name
  let r = fnamemodify(RailsRoot(),':~')
  let r = s:gsub(r,'^\~','0')
  let r = s:gsub(r,'\W','_')
  let r = s:gsub(r,'^\d','_&')
  return r
endfunction

function! s:gbopt(opt)
  " Get buffer option
  if exists("b:".s:sname()."_".a:opt)
    return b:{s:sname()}_{a:opt}
  elseif exists("s:_".s:rv()."_".s:environment()."_".a:opt)
    return s:_{s:rv()}_{s:environment()}_{a:opt}
  elseif exists("g:".s:sname()."_".a:opt)
    return g:{s:sname()}_{a:opt}
  else
    return ""
  endif
endfunction

function! s:saopt(opt,val)
  " Set an application option
  let s:_{s:rv()}_{s:environment()}_{a:opt} = a:val
endfunction

function! s:sname()
  return fnamemodify(s:file,':t:r')
endfunction

function! s:rquote(str)
  " Imperfect but adequate for Ruby arguments
  if a:str =~ '^[A-Za-z0-9_/.-]\+$'
    return a:str
  elseif &shell =~? 'cmd'
    return '"'.s:gsub(s:gsub(a:str,'\','\\'),'"','\\"').'"'
  else
    return "'".s:gsub(s:gsub(a:str,'\','\\'),"'","'\\\\''")."'"
  endif
endfunction

function! s:rubyexestr(cmd)
  return "ruby -C ".s:rquote(RailsRoot())." ".a:cmd
endfunction

function! s:rubyexe(cmd,...)
  if a:0 && has("gui_win32")
    exe "!start ".s:esccmd(s:rubyexestr(a:cmd))
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
  let cmd = s:rubyexestr('-e '.s:rquote('require %{rubygems} rescue nil; require %{active_support} rescue nil; '.a:ruby))
  "let g:rails_last_ruby_command = cmd
  " If the shell is messed up, this command could cause an error message
  silent! let results = system(cmd)
  "let g:rails_last_ruby_result = results
  if results =~ '-e:\d'
    return def
  else
    return results
  endif
endfunction

function! s:lastmethodline()
  let line = line(".")
  while line > 0 && getline(line) !~ &l:define
    let line = line - 1
  endwhile
  return line
endfunction

function! s:lastmethod()
  let line = s:lastmethodline()
  if line
    return matchstr(getline(line),'\%('.&define.'\)\zs\k\%(\k\|:\)*')
  else
    return ""
  endif
endfunction

function! s:controller()
  let t = RailsFileType()
  let f = RailsFilePath()
  if f =~ '\<app/views/layouts/'
    return s:sub(f,'.*\<app/views/layouts/\(.\{-\}\)\.\k\+$','\1')
  elseif f =~ '\<app/views/'
    return s:sub(f,'.*\<app/views/\(.\{-\}\)/\k\+\.\k\+$','\1')
  elseif f =~ '\<app/helpers/.*_helper\.rb$'
    return s:sub(f,'.*\<app/helpers/\(.\{-\}\)_helper\.rb$','\1')
  elseif f =~ '\<app/controllers/.*_controller\.rb$'
    return s:sub(f,'.*\<app/controllers/\(.\{-\}\)_controller\.rb$','\1')
  elseif f =~ '\<app/apis/.*_api\.rb$'
    return s:sub(f,'.*\<app/apis/\(.\{-\}\)_api\.rb$','\1')
  elseif f =~ '\<test/functional/.*_controller_test\.rb$'
    return s:sub(f,'.*\<test/functional/\(.\{-\}\)_controller_test\.rb$','\1')
  elseif f =~ '\<components/.*_controller\.rb$'
    return s:sub(f,'.*\<components/\(.\{-\}\)_controller\.rb$','\1')
  elseif f =~ '\<components/.*\.\(rhtml\|rxml\|rjs\|mab\)$'
    return s:sub(f,'.*\<components/\(.\{-\}\)/\k\+\.\k\+$','\1')
  endif
  return ""
endfunction

function! s:usesubversion()
  if exists("b:rails_use_subversion")
    return b:rails_use_subversion
  else
    let b:rails_use_subversion = g:rails_subversion && 
          \ (RailsRoot()!="") && isdirectory(RailsRoot()."/.svn")
    return b:rails_use_subversion
  endif
endfunction

function! s:environment()
  if exists('$RAILS_ENV')
    return $RAILS_ENV
  else
    return "development"
  endif
endfunction

function! s:environments(...)
  return "development\ntest\nproduction"
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

" }}}1
" "Public" Interface {{{1

" RailsRoot() is the only official public function

function! RailsRoot()
  if exists("b:rails_root")
    return b:rails_root
  else
    return ""
  endif
endfunction

function! RailsAppPath()
  " Deprecated
  return RailsRoot()
endfunction

function! RailsFilePath()
  if !exists("b:rails_root")
    return ""
  elseif exists("b:rails_file_path")
    return b:rails_file_path
  endif
  let f = s:gsub(expand("%:p"),'\\ \@!','/')
  if s:gsub(b:rails_root,'\\ \@!','/') == strpart(f,0,strlen(b:rails_root))
    return strpart(f,strlen(b:rails_root)+1)
  else
    return f
  endif
endfunction

function! RailsFileType()
  if !exists("b:rails_root")
    return ""
  elseif exists("b:rails_file_type")
    return b:rails_file_type
  endif
  let f = RailsFilePath()
  let e = fnamemodify(RailsFilePath(),':e')
  let r = ""
  let top = getline(1)." ".getline(2)." ".getline(3)." ".getline(4)." ".getline(5)
  if f == ""
    let r = f
  elseif f =~ '_controller\.rb$' || f =~ '\<app/controllers/application\.rb$'
    if top =~ '\<wsdl_service_name\>'
      let r = "controller-api"
    else
      let r = "controller"
    endif
  elseif f =~ '_api\.rb'
    let r = "api"
  elseif f =~ '\<test/test_helper\.rb$'
    let r = "test"
  elseif f =~ '_helper\.rb$'
    let r = "helper"
  elseif f =~ '\<app/models\>'
    let class = matchstr(top,'\<Acti\w\w\u\w\+\%(::\h\w*\)\+\>')
    if class != ''
      let class = s:sub(class,'::Base$','')
      let class = tolower(s:gsub(class,'[^A-Z]',''))
      let r = "model-".class
    elseif f =~ '_mailer\.rb$'
      let r = "model-am"
    elseif top =~ '\<\%(validates_\w\+_of\|set_\%(table_name\|primary_key\)\)\>'
      let r = "model-ar"
    else
      let r = "model"
    endif
  elseif f =~ '\<app/views/layouts\>.*\.'
    let r = "view-layout-" . e
  elseif f =~ '\<\%(app/views\|components\)/.*/_\k\+\.\k\+$'
    let r = "view-partial-" . e
  elseif f =~ '\<app/views\>.*\.' || f =~ '\<components/.*/.*\.\(rhtml\|rxml\|rjs\|mab\)'
    let r = "view-" . e
  elseif f =~ '\<test/unit/.*_test\.rb'
    let r = "test-unit"
  elseif f =~ '\<test/functional/.*_test\.rb'
    let r = "test-functional"
  elseif f =~ '\<test/integration/.*_test\.rb'
    let r = "test-integration"
  elseif f =~ '\<test/fixtures\>'
    if e == "yml"
      let r = "fixtures-yaml"
    else
      let r = "fixtures-" . e
    endif
  elseif f =~ '\<db/migrate\>' || f=~ '\<db/schema\.rb$'
    let r = "migration"
  elseif f =~ '\<lib/tasks\>' || f=~ '\<Rakefile$'
    let r = "task"
  elseif f =~ '\<log/.*\.log$'
    let r = "log"
  elseif e == "css" || e == "js" || e == "html"
    let r = e
  endif
  return r
endfunction

" }}}1
" Configuration {{{1

function! s:SetOptDefault(opt,val)
  if !exists("g:".a:opt)
    exe "let g:".a:opt." = '".a:val."'"
  endif
endfunction

function! s:InitConfig()
  call s:SetOptDefault("rails_level",3)
  let l = g:rails_level
  call s:SetOptDefault("rails_statusline",l>2)
  call s:SetOptDefault("rails_syntax",l>1)
  call s:SetOptDefault("rails_isfname",0)
  call s:SetOptDefault("rails_mappings",l>2)
  call s:SetOptDefault("rails_abbreviations",l>4)
  call s:SetOptDefault("rails_expensive",l>(2+(has("win32")||has("win32unix"))))
  call s:SetOptDefault("rails_dbext",g:rails_expensive)
  call s:SetOptDefault("rails_avim_commands",l>2)
  call s:SetOptDefault("rails_subversion",l>3)
  call s:SetOptDefault("rails_tabstop",0)
  call s:SetOptDefault("rails_default_file","README")
  call s:SetOptDefault("rails_default_database","")
  call s:SetOptDefault("rails_leader","<LocalLeader>r")
  call s:SetOptDefault("rails_url",'http://localhost:3000/')
  call s:SetOptDefault("rails_modelines",l>3)
  call s:SetOptDefault("rails_menu",(l>2)+(l>3))
  call s:SetOptDefault("rails_debug",0)
  if l > 2
    if exists("g:loaded_dbext") && executable("sqlite3") && ! executable("sqlite")
      " Since dbext can't find it by itself
      call s:SetOptDefault("dbext_default_SQLITE_bin","sqlite3")
    endif
  endif
  if l > 3
    "call s:SetOptDefault("ruby_no_identifiers",1)
    call s:SetOptDefault("rubycomplete_rails",1)
  endif
endfunction

" }}}1
" Autocommand Functions {{{1

function! s:QuickFixCmdPre()
  if exists("b:rails_root")
    if strpart(getcwd(),0,strlen(RailsRoot())) != RailsRoot()
      let s:last_dir = getcwd()
      echo "lchdir ".s:ra()
      exe "lchdir ".s:ra()
    endif
  endif
endfunction

function! s:QuickFixCmdPost()
  if exists("s:last_dir")
    exe "lchdir ".s:escarg(s:last_dir)
    unlet s:last_dir
  endif
endfunction

function! s:BufEnter()
  if exists("b:rails_root")
    if g:rails_isfname
      let b:rails_restore_isfname=&isfname
      set isfname=@,48-57,/,-,_,\",',:
    endif
    if exists("+completefunc") && &completefunc == 'syntaxcomplete#Complete'
      if exists("g:loaded_syntax_completion")
        " Ugly but necessary, until we have our own completion
        unlet g:loaded_syntax_completion
        silent! delfunction syntaxcomplete#Complete
      endif
    endif
    call s:menuBufEnter()
    call s:BufDatabase(-1)
  else
    if isdirectory(expand('%;p'))
      call s:Detect(expand('%:p'))
    endif
  endif
endfunction

function! s:BufLeave()
  if exists("b:rails_restore_isfname")
    let &isfname=b:rails_restore_isfname
    unlet b:rails_restore_isfname
  endif
  call s:menuBufLeave()
endfunction

function! s:tabstop()
  if !exists("b:rails_root")
    return 0
  elseif &filetype != 'ruby' && &filetype != 'eruby' && &filetype != 'html' && &filetype != 'css' && &filetype != 'yaml'
    return 0
  elseif exists("b:rails_tabstop")
    return b:rails_tabstop
  else
    return g:rails_tabstop
  endif
endfunction

function! s:breaktabs()
  let ts = s:tabstop()
  if ts
    if exists("s:retab_in_process")
      unlet s:retab_in_process
      let line = line('.')
      lockmarks silent! undo
      lockmarks exe line
    else
      let &l:tabstop = 2
      setlocal noexpandtab
      let mod = &l:modifiable
      setlocal modifiable
      let line = line('.')
      " FIXME: when I say g/^\s/, only apply to those lines
      lockmarks g/^\s/retab!
      lockmarks exe line
      let &l:modifiable = mod
    endif
    let &l:tabstop = ts
    let &l:softtabstop = ts
    let &l:shiftwidth = ts
  endif
endfunction

function! s:fixtabs()
  let ts = s:tabstop()
  if ts && ! &l:expandtab && !exists("s:retab_in_process")
    if 0
      undojoin
    else
      let s:retab_in_process = 1
    endif
    let &l:tabstop = 2
    setlocal expandtab
    let line = line('.')
    lockmarks retab
    lockmarks exe line
    let &l:tabstop = ts
  endif
endfunction

" }}}1
" Commands {{{1

function! s:BufCommands()
  let rp = s:ra()
  call s:BufScriptWrappers()
  call s:BufNavCommands()
  command! -buffer -bar -complete=custom,s:RakeComplete -nargs=? Rake :call s:Rake(<bang>0,<q-args>)
  command! -buffer -bar -complete=custom,s:PreviewComplete -bang -nargs=? Rpreview :call s:Preview(<bang>0,<q-args>)
  command! -buffer -bar -complete=custom,s:environments -bang -nargs=? Rlog :call s:Log(<bang>0,<q-args>)
  command! -buffer -bar -nargs=? Rmigration :call s:Migration(<bang>0,"edit",<q-args>)
  command! -buffer -bar -nargs=* Rcontroller :call s:ControllerFunc(<bang>0,"app/controllers/","_controller.rb",<f-args>)
  command! -buffer -bar -nargs=* Rhelper :call s:ControllerFunc(<bang>0,"app/helpers/","_helper.rb",<f-args>)
  command! -buffer -bar -nargs=* Rlayout :call s:LayoutFunc(<bang>0,<f-args>)
  command! -buffer -bar -nargs=0 Rtags :call s:Tags(<bang>0)
  command! -buffer -bar -bang -complete=custom,s:RsetComplete -nargs=* Rset :call s:Rset(<bang>0,<f-args>)
  if exists(":Project")
    command! -buffer -bar -bang -nargs=? Rproject :call s:Project(<bang>0,<q-args>)
  endif
  if exists("g:loaded_dbext")
    command! -buffer -bar -nargs=? -bang Rdbext :call s:BufDatabase(2,<q-args>,<bang>0)
  endif
  let ext = expand("%:e")
  if ext == "rhtml" || ext == "rxml" || ext == "rjs" || ext == "mab"
    command! -buffer -bar -nargs=? -range Rpartial :<line1>,<line2>call s:MakePartial(<bang>0,<f-args>)
  endif
endfunction

function! s:Rake(bang,arg) " {{{2
  let t = RailsFileType()
  let arg = a:arg
  if &filetype == "ruby" && arg == '' && g:rails_modelines
    let lnum = s:lastmethodline()
    let str = getline(lnum)."\n".getline(lnum+1)."\n".getline(lnum+2)."\n"
    let pat = '\s\+\zs.\{-\}\ze\%(\n\|\s\s\|#{\@!\|$\)'
    let mat = matchstr(str,'#\s*rake'.pat)
    let mat = s:sub(mat,'\s\+$','')
    if mat != ""
      let arg = mat
    endif
  endif
  if arg == ''
    if exists("b:rails_rake_task")
      let arg = b:rails_rake_task
    elseif exists("b:rails_default_rake_target")
      call s:warn("b:rails_default_rake_target is deprecated.  :Rset rake_task=... instead")
      let arg = b:rails_default_rake_target
    endif
  endif
  if arg == "stats"
    " So you can see it in Windows
    call s:QuickFixCmdPre()
    exe "!".&makeprg." stats"
    call s:QuickFixCmdPost()
  elseif arg =~ '^preview\>'
    exe 'R'.s:gsub(arg,':','/')
  elseif arg =~ '^runner:'
    " FIXME: set a proper 'efm'
    let arg = s:sub(arg,'^runner:','')
    let old_make = &makeprg
    let &l:makeprg = s:rubyexestr("script/runner ".s:rquote(s:esccmd(arg)))
    echo &l:makeprg
    make
    "exe 'Rrunner '.arg
    let &l:makeprg = old_make
  elseif arg != ''
    exe 'make '.a:arg
  elseif t =~ '^task\>'
    let lnum = s:lastmethodline()
    let line = getline(ln)
    " We can't grab the namespace so only run tasks at the start of the line
    if line =~ '^\%(task\|file\)\>'
      exe 'make '.s:lastmethod()
    else
      make
    endif
  elseif t =~ '^test\>'
    let meth = s:lastmethod()
    if meth =~ '^test_'
      let call = " TESTOPTS=-n/".meth."/"
    else
      let call = ""
    endif
    exe "make ".s:sub(s:gsub(t,'-',':'),'unit$\|functional$','&s')." TEST=\"%:p\"".call
  elseif t=~ '^migration\>' && RailsFilePath() !~ '\<db/schema\.rb$'
    make db:migrate
  elseif t=~ '^model\>'
    make test:units TEST="%:p:r:s?[\/]app[\/]models[\/]?/test/unit/?_test.rb"
  elseif t=~ '^\<\%(controller\|helper\|view\)\>'
    make test:functionals
  else
    make
  endif
endfunction

function! s:raketasks()
  return "db:fixtures:load\ndb:migrate\ndb:schema:dump\ndb:schema:load\ndb:sessions:clear\ndb:sessions:create\ndb:structure:dump\ndb:test:clone\ndb:test:clone_structure\ndb:test:prepare\ndb:test:purge\ndoc:app\ndoc:clobber_app\ndoc:clobber_plugins\ndoc:clobber_rails\ndoc:plugins\ndoc:rails\ndoc:reapp\ndoc:rerails\nlog:clear\nrails:freeze:edge\nrails:freeze:gems\nrails:unfreeze\nrails:update\nrails:update:configs\nrails:update:javascripts\nrails:update:scripts\nstats\ntest\ntest:functionals\ntest:integration\ntest:plugins\ntest:recent\ntest:uncommitted\ntest:units\ntmp:cache:clear\ntmp:clear\ntmp:create\ntmp:sessions:clear\ntmp:sockets:clear"
endfunction

function! s:RakeComplete(A,L,P)
  return s:raketasks()
endfunction " }}}2

function! s:Preview(bang,arg) " {{{2
  let root = s:gbopt("url")
  if root == ''
    let root = s:gbopt("root_url")
  endif
  let root = s:sub(root,'/$','')
  if a:arg =~ '://'
    let uri = a:arg
  elseif a:arg != ''
    let uri = root.'/'.s:sub(a:arg,'^/','')
  else
    let uri = root.'/'
    if s:controller() != '' && s:controller() != 'application'
      let uri = uri.s:controller().'/'
      if RailsFileType() =~ '^view\%(-partial\|-layout\)\@!'
        let uri = uri.expand('%:t:r').'/'
      elseif RailsFileType() =~ '^controller\>' && s:lastmethod() != ''
        let uri = uri.s:lastmethod().'/'
      endif
    endif
  endif
  if !exists(":OpenURL")
    if has("gui_mac")
      command -bar -nargs=1 OpenURL :!open <args>
    elseif has("gui_win32")
      command -bar -nargs=1 OpenURL :!start cmd /cstart /b <args>
    endif
  endif
  if exists(':OpenURL') && !a:bang
    exe 'OpenURL '.uri
  else
    " Work around bug where URLs with out ? get handled as FTP
    let url = uri.(uri =~ '?' ? '' : '?')
    exe 'pedit '.url
    wincmd w
    if &filetype == ''
      setlocal filetype=xhtml
    endif
    call s:Detect(RailsRoot())
    map <buffer> <silent> q :bwipe<CR>
    wincmd p
    if !a:bang
      call s:warn("Define a :OpenURL command to use a browser")
    endif
  endif
endfunction

function! s:PreviewComplete(A,L,P)
  let ret = ''
  if s:controller() != '' && s:controller() != 'application'
    let ret = s:controller().'/'
    if RailsFileType() =~ '^view\%(-partial\|-layout\)\@!'
      let ret = ret.expand('%:t:r').'/'
    elseif RailsFileType() =~ '^controller\>' && s:lastmethod() != ''
      let ret = ret.s:lastmethod().'/'
    endif
  endif
  return ret
endfunction " }}}2

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
      exe "Tail ".s:ra().'/'.lf
    else
      exe "pedit ".s:ra().'/'.lf
      "exe "sfind ".lf
    endif
  endif
endfunction

function! s:Project(bang,arg) " {{{2
  let rr = RailsRoot()
  exe "Project ".a:arg
  let line = search('^[^ =]*="'.s:gsub(rr,'[\/]','[\\/]').'"')
  let projname = s:gsub(fnamemodify(rr,':t'),'=','-') " .'_on_rails'
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
    let views = s:RealMansGlob(a:rr.'/app/views','*')."\n"
    while views != ''
      let dir = matchstr(views,'^.\{-\}\ze\n')
      let views = s:sub(views,'^.\{-\}\n','')
      let str = str."   ".dir."=".dir.' glob="**" {'."\n   }\n"
    endwhile
    let str = str."  }\n"
  else
    let str = str."  views=views filter=\"**\" {\n  }\n"
  endif
  let str = str . " }\n components=components filter=\"**\" {\n }\n"
  let str = str . " config=config {\n  environments=environments {\n  }\n }\n"
  let str = str . " db=db {\n"
  if isdirectory(a:rr.'/db/migrate')
    let str = str . "  migrate=migrate {\n  }\n"
  endif
  let str = str . " }\n"
  let str = str . " lib=lib {\n  tasks=tasks {\n  }\n }\n"
  let str = str . " public=public {\n  images=images {\n  }\n  javascripts=javascripts {\n  }\n  stylesheets=stylesheets {\n  }\n }\n"
  let str = str . " test=test {\n  fixtures=fixtures filter=\"**\" {\n  }\n  functional=functional filter=\"**\" {\n  }\n"
  if isdirectory(a:rr.'/test/integration')
    let str = str . "  integration=integration filter=\"**\" {\n  }\n"
  endif
  let str = str . "  mocks=mocks filter=\"**\" {\n  }\n  unit=unit filter=\"**\" {\n  }\n }\n}\n"
  return str
endfunction " }}}2

function! s:Migration(bang,cmd,arg)
  if a:arg =~ '^\d$'
    let glob = '00'.a:arg.'_*.rb'
  elseif a:arg =~ '^\d\d$'
    let glob = '0'.a:arg.'_*.rb'
  elseif a:arg =~ '^\d\d\d$'
    let glob = ''.a:arg.'_*.rb'
  elseif a:arg == ''
    let glob = '*.rb'
  else
    let glob = '*'.a:arg.'*.rb'
  endif
  let migr = s:sub(glob(RailsRoot().'/db/migrate/'.glob),'.*\n','')
  if migr != ''
    exe a:cmd." ".s:escarg(migr)
  else
    return s:error("Migration not found".(a:arg=='' ? '' : ': '.a:arg))
  endif
endfunction

function! s:NewApp(bang,...)
  if a:0 == 0
    !rails
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
    exe "edit ".s:escarg(dir)."/".g:rails_default_file
  endif
endfunction

function! s:findlayout(name)
  let c = a:name
  if filereadable(RailsRoot()."/app/views/layouts/".c.".rhtml")
    let file = "/app/views/layouts/".c.".rhtml"
  elseif filereadable(RailsRoot()."/app/views/layouts/".c.".rxml")
    let file = "/app/views/layouts/".c.".rxml"
  elseif filereadable(RailsRoot()."/app/views/layouts/".c.".mab")
    let file = "/app/views/layouts/".c.".mab"
  else
    let file = ""
  endif
  return file
endfunction

function! s:LayoutFunc(bang,...)
  if a:0
    let c = s:sub(s:RailsIncludefind(s:sub(a:1,'^.','\u&')),'\.rb$','')
  else
    let c = s:controller()
  endif
  if c == ""
    return s:error("No layout name given")
  endif
  let file = s:findlayout(c)
  if file == ""
    let file = s:findlayout("application")
  endif
  if file == ""
    let file = "/app/views/layouts/application.rhtml"
  endif
  let cmd = "edit".(a:bang?"! ":' ').s:ra().file
  exe cmd
endfunction

function! s:ControllerFunc(bang,prefix,suffix,...)
  if a:0
    let c = s:sub(s:RailsIncludefind(s:sub(a:1,'^.','\u&')),'\.rb$','')
  else
    let c = s:controller()
  endif
  if c == ""
    return s:error("No controller name given")
  endif
  let cmd = "edit".(a:bang?"! ":' ').s:ra().'/'.a:prefix.c.a:suffix
  exe cmd
  if a:0 > 1
    exe "silent! djump ".a:2
  endif
endfunction

function! s:Rset(bang,...)
  let c = 1
  while c <= a:0
    let arg = a:{c}
    let c = c + 1
    if arg !~ '='
      if exists("b:".s:sname()."_".arg) || exists("s:_".s:rv()."_".s:environment()."_".arg)
        echo arg."=".s:gbopt(arg)
      else
        call s:error("No such rails.vim option: ".arg)
      endif
    else
      let opt = matchstr(arg,'[^=]*')
      let val = s:sub(arg,'^[^=]*=','')
      if a:bang
        let b:rails_{opt} = val
      else
        "call s:saopt(opt,val)
        let b:rails_{opt} = val
      endif
    endif
  endwhile
endfunction

function! s:RsetComplete(A,L,P)
  if a:A =~ '='
    let opt = matchstr(a:A,'[^=]*')
    return opt."=".s:gbopt(opt)
  else
    return "rake_task=\nurl="
  endif
  return ""
endfunction

function! s:RealMansGlob(path,glob)
  " HOW COULD SUCH A SIMPLE OPERATION BE SO COMPLICATED?
  if a:path =~ '[\/]$'
    let path = a:path
  else
    let path = a:path . '/'
  endif
  let badres = glob(path.a:glob)
  let goodres = ""
  while strlen(badres) > 0
    let idx = stridx(badres,"\n")
    if idx == -1
      let idx = strlen(badres)
    endif
    let tmp = strpart(badres,0,idx+1)
    let badres = strpart(badres,idx+1)
    let goodres = goodres.strpart(tmp,strlen(path))
  endwhile
  return goodres
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

" }}}1
" Script Wrappers {{{1

function! s:BufScriptWrappers()
  if has("gui_win32")
    " Poor win32 users, let's allow background tasks since their shell sucks
    command! -buffer -bar -complete=custom,s:ScriptComplete -nargs=+ -bang Rscript :call s:Script(<bang>0,<f-args>)
    command! -buffer -bar -complete=custom,s:ConsoleComplete -nargs=* Rconsole :Rscript! console <args>
    command! -buffer -bar -nargs=* Rbreakpointer :Rscript! breakpointer <args>
  else
    command! -buffer -bar -complete=custom,s:ScriptComplete -nargs=+ Rscript :call s:Script(<bang>0,<f-args>)
    command! -buffer -bar -complete=custom,s:ConsoleComplete -nargs=* Rconsole :Rscript console <args>
    command! -buffer -bar -nargs=* Rbreakpointer :Rscript breakpointer <args>
  endif
  command! -buffer -bar -complete=custom,s:GenerateComplete -nargs=* Rgenerate :call s:Generate(<bang>0,<f-args>)
  command! -buffer -bar -complete=custom,s:DestroyComplete -nargs=* Rdestroy :call s:Destroy(<bang>0,<f-args>)
  command! -buffer -bar -complete=custom,s:PluginComplete -nargs=* Rplugin :call s:Plugin(<bang>0,<f-args>)
  command! -buffer -bar -complete=custom,s:environments -nargs=? -bang Rserver :call s:Server(<bang>0,<q-args>)
  command! -buffer -nargs=1 Rrunner :call s:Script(<bang>0,"runner",<f-args>)
  command! -buffer -nargs=1 Rp      :call s:Script(<bang>0,"runner","p begin ".<f-args>." end")
endfunction

function! s:Script(bang,cmd,...)
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:rquote(a:{c})
    let c = c + 1
  endwhile
  if a:bang
    call s:rubyexe(s:rquote("script/".a:cmd).str,1)
  else
    call s:rubyexe(s:rquote("script/".a:cmd).str)
  endif
endfunction

function! s:Server(bang,arg)
  let port = matchstr(a:arg,'-p\s*\zs\d\+')
  if port == ''
    let port = "3000"
  endif
  let bind = "0.0.0.0"
  if a:bang && executable("ruby")
    if has("win32") || has("win64")
      let netstat = system("netstat -anop tcp")
      let pid = matchstr(netstat,'\<'.bind.':'.port.'\>.\{-\}LISTENING\s\+\zs\d\+')
    elseif executable('lsof')
      let pid = system("lsof -ti 4tcp@".bind.":".port)
      let pid = s:sub(pid,'\n','')
    else
      let pid = ""
    endif
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
  if has("win32") || has("win64")
    exe "!start ".s:rubyexestr(s:rquote("script/server")." ".a:arg)
  else
    call s:rubyexe(s:rquote("script/server")." ".a:arg." --daemon")
  endif
  call s:saopt('url','http://'.(bind=='0.0.0.0'?'localhost': bind).':'.port.'/')
endfunction

function! s:Plugin(bang,...)
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:rquote(a:{c})
    let c = c + 1
  endwhile
  if s:usesubversion() && a:0 && a:1 == 'install'
    call s:rubyexe(s:rquote("script/plugin").str.' -x')
  else
    call s:rubyexe(s:rquote("script/plugin").str)
  endif
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
  if str !~ '-p\>'
    let execstr = s:rubyexestr("script/generate ".target." -p -f".str)
    let res = system(execstr)
    let file = matchstr(res,'\s\+\%(create\|force\)\s\+\zs\f\+\.rb\ze\n')
    if file == ""
      let file = matchstr(res,'\s\+\%(exists\)\s\+\zs\f\+\.rb\ze\n')
    endif
    echo file
  else
    let file = ""
  endif
  if !s:rubyexe("script/generate ".target.(s:usesubversion()?' -c':'').str) && file != ""
    exe "edit ".s:ra()."/".file
  endif
endfunction

function! s:generators()
  return "controller\nintegration_test\nmailer\nmigration\nmodel\nplugin\nscaffold\nsession_migration\nweb_service"
endfunction

function! s:ScriptComplete(ArgLead,CmdLine,P)
  "  return s:gsub(glob(RailsRoot()."/script/**"),'\%(.\%(\n\)\@<!\)*[\/]script[\/]','')
  let cmd = s:sub(a:CmdLine,'^\u\w*\s\+','')
"  let g:A = a:ArgLead
"  let g:L = cmd
"  let g:P = a:P
  if cmd !~ '^[ A-Za-z0-9_-]*$'
    " You're on your own, bud
    return ""
  elseif cmd =~ '^\w*$'
    return "about\nbreakpointer\nconsole\ndestroy\ngenerate\nperformance/benchmarker\nperformance/profiler\nplugin\nproccess/reaper\nprocess/spawner\nrunner\nserver"
  elseif cmd =~ '^\%(generate\|destroy\)\s\+'.a:ArgLead."$"
    return s:generators()
  elseif cmd =~ '^\%(console\)\s\+\(--\=\w\+\s\+\)\='.a:ArgLead."$"
    return s:environments()."\n-s\n--sandbox"
  elseif cmd =~ '^\%(plugin\)\s\+'.a:ArgLead."$"
    return "discover\nlist\ninstall\nupdate\nremove\nsource\nunsource\nsources"
  endif
  return ""
"  return s:RealMansGlob(RailsRoot()."/script",a:ArgLead."*")
endfunction

function! s:CustomComplete(A,L,P,cmd)
  let L = "Script ".a:cmd." ".s:sub(a:L,'^\h\w*\s\+','')
  let P = a:P - strlen(a:L) + strlen(L)
  return s:ScriptComplete(a:A,L,P)
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

function! s:PluginComplete(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"plugin")
endfunction

" }}}1
" Syntax {{{1

function! s:BufSyntax()
  if (!exists("g:rails_syntax") || g:rails_syntax) && (exists("g:syntax_on") || exists("g:syntax_manual"))
    let t = RailsFileType()
    if !exists("s:rails_view_helpers")
      if g:rails_expensive
        let s:rails_view_helpers = s:rubyeval('require %{action_view}; puts ActionView::Helpers.constants.grep(/Helper$/).collect {|c|ActionView::Helpers.const_get c}.collect {|c| c.public_instance_methods(false)}.flatten.sort.uniq.reject {|m| m =~ /[=?]$/}.join(%{ })',"link_to")
      else
        let s:rails_view_helpers = "link_to"
      endif
    endif
    "let g:rails_view_helpers = s:rails_view_helpers
    let rails_view_helpers = '+\.\@<!\<\('.s:gsub(s:rails_view_helpers,'\s\+','\\|').'\)\>+'
    if &syntax == 'ruby'
      syn keyword rubyRailsMethod breakpoint
      if t != ''
        syn match rubyRailsError ':order_by\>'
      endif
      if t == ''
        syn keyword rubyRailsMethod params request response session headers template cookies flash
      endif
      if t =~ '^api\>'
        syn keyword rubyRailsAPIMethod api_method
      endif
      if t =~ '^model$' || t =~ '^model-ar\>'
        syn keyword rubyRailsARMethod acts_as_list acts_as_nested_set acts_as_tree composed_of
        syn keyword rubyRailsARAssociationMethod belongs_to has_one has_many has_and_belongs_to_many
        "syn match rubyRailsARCallbackMethod '\<\(before\|after\)_\(create\|destroy\|save\|update\|validation\|validation_on_create\|validation_on_update\)\>'
        syn keyword rubyRailsARCallbackMethod before_create before_destroy before_save before_update before_validation before_validation_on_create before_validation_on_update
        syn keyword rubyRailsARCallbackMethod after_create after_destroy after_save after_update after_validation after_validation_on_create after_validation_on_update
        syn keyword rubyRailsARClassMethod attr_accessible attr_protected establish_connection set_inheritance_column set_locking_column set_primary_key set_sequence_name set_table_name
        "syn keyword rubyRailsARCallbackMethod after_find after_initialize
        syn keyword rubyRailsARValidationMethod validate validate_on_create validate_on_update validates_acceptance_of validates_associated validates_confirmation_of validates_each validates_exclusion_of validates_format_of validates_inclusion_of validates_length_of validates_numericality_of validates_presence_of validates_size_of validates_uniqueness_of
      endif
      if t =~ '^controller\>' || t =~ '^view\>' || t=~ '^helper\>'
        syn keyword rubyRailsMethod params request response session headers template cookies flash
        syn match rubyRailsError '[@:]\@<!@\%(params\|request\|response\|session\|headers\|template\|cookies\|flash\)\>'
        syn match rubyRailsError '\<render_partial\>'
        syn keyword rubyRailsRenderMethod render render_component
      endif
      if t =~ '^helper\>' || t=~ '^view\>'
        "exe "syn match rubyRailsHelperMethod ".rails_view_helpers
        exe "syn keyword rubyRailsHelperMethod ".s:sub(s:rails_view_helpers,'\<select\s\+','')
        syn match rubyRailsHelperMethod '\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!'
      elseif t =~ '^controller\>'
        syn keyword rubyRailsControllerHelperMethod helper helper_attr helper_method filter layout url_for scaffold observer service model serialize
        syn match rubyRailsControllerDeprecatedMethod '\<render_\%(action\|text\|file\|template\|nothing\|without_layout\)\>'
        syn keyword rubyRailsRenderMethod render_to_string render_component_as_string redirect_to
        syn keyword rubyRailsFilterMethod before_filter append_before_filter prepend_before_filter after_filter append_after_filter prepend_after_filter around_filter append_around_filter prepend_around_filter skip_before_filter skip_after_filter
        syn keyword rubyRailsFilterMethod verify
      endif
      if t =~ '^migration\>'
        syn keyword rubyRailsMigrationMethod create_table drop_table rename_table add_column rename_column change_column remove_column add_index remove_index
      endif
      if t =~ '^test\>'
        syn keyword rubyRailsTestMethod add_assertion assert assert_block assert_equal assert_in_delta assert_instance_of assert_kind_of assert_match assert_nil assert_no_match assert_not_equal assert_not_nil assert_not_same assert_nothing_raised assert_nothing_thrown assert_operator assert_raise assert_respond_to assert_same assert_send assert_throws flunk fixtures use_transactional_fixtures use_instantiated_fixtures
        if t !~ '^test-unit\>'
          syn match   rubyRailsTestControllerMethod  '\.\@<!\<\%(get\|post\|put\|delete\|head\|process\)\>'
          syn keyword rubyRailsTestControllerMethod assert_response assert_redirected_to assert_template assert_recognizes assert_generates assert_routing assert_tag assert_no_tag assert_dom_equal assert_dom_not_equal assert_valid
        endif
      endif
      if t =~ '^task\>'
        syn match rubyRailsRakeMethod '^\s*\zs\%(task\|file\|desc\)\>\%(\s*=\)\@!'
      endif
      syn keyword rubyRailsMethod cattr_accessor mattr_accessor
      syn keyword rubyRailsInclude require_dependency require_gem
    elseif &syntax == "eruby" && t =~ '^view\>'
      syn match rubyRailsError ':order_by\>'
      "syn match rubyRailsError '@content_for_\w*\>'
      syn cluster erubyRailsRegions contains=erubyOneLiner,erubyBlock,erubyExpression
      "exe "syn match erubyRailsHelperMethod ".rails_view_helpers." contained containedin=@erubyRailsRegions"
        exe "syn keyword erubyRailsHelperMethod ".s:sub(s:rails_view_helpers,'\<select\s\+','')." contained containedin=@erubyRailsRegions"
        syn match erubyRailsHelperMethod '\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!' contained containedin=@erubyRailsRegions
      syn keyword erubyRailsMethod breakpoint
      syn keyword erubyRailsMethod params request response session headers template cookies flash contained containedin=@erubyRailsRegions
      syn match erubyRailsMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' contained containedin=@erubyRailsRegions
        syn keyword erubyRailsRenderMethod render render_component contained containedin=@erubyRailsRegions
      syn match rubyRailsError '[^@:]\@<!@\%(params\|request\|response\|session\|headers\|template\|cookies\|flash\)\>' contained containedin=@erubyRailsRegions
    elseif &syntax == "yaml"
      " Modeled after syntax/eruby.vim
      unlet b:current_syntax
      let g:main_syntax = 'eruby'
      syn include @rubyTop syntax/ruby.vim
      unlet g:main_syntax
      syn cluster erubyRegions contains=yamlRailsOneLiner,yamlRailsBlock,yamlRailsExpression,yamlRailsComment
      syn cluster erubyRailsRegions contains=yamlRailsOneLiner,yamlRailsBlock,yamlRailsExpression
      syn region  yamlRailsOneLiner   matchgroup=yamlRailsDelimiter start="^%%\@!" end="$"  contains=@rubyRailsTop	containedin=ALLBUT,@yamlRailsRegions keepend oneline
      syn region  yamlRailsBlock      matchgroup=yamlRailsDelimiter start="<%%\@!" end="%>" contains=@rubyTop		containedin=ALLBUT,@yamlRailsRegions
      syn region  yamlRailsExpression matchgroup=yamlRailsDelimiter start="<%="    end="%>" contains=@rubyTop		containedin=ALLBUT,@yamlRailsRegions
      syn region  yamlRailsComment    matchgroup=yamlRailsDelimiter start="<%#"    end="%>" contains=rubyTodo,@Spell	containedin=ALLBUT,@yamlRailsRegions keepend
        syn match yamlRailsMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' containedin=@erubyRailsRegions
      let b:current_syntax = "yaml"
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
  hi def link rubyRailsMigrationMethod        rubyRailsMethod
  hi def link rubyRailsControllerHelperMethod rubyRailsMethod
  hi def link rubyRailsControllerDeprecatedMethod rubyRailsError
  hi def link rubyRailsFilterMethod           rubyRailsMethod
  hi def link rubyRailsTestControllerMethod   rubyRailsTestMethod
  hi def link rubyRailsTestMethod             rubyRailsMethod
  hi def link rubyRailsRakeMethod             rubyRailsMethod
  hi def link rubyRailsMethod                 railsMethod
  hi def link rubyRailsError                  rubyError
  hi def link rubyRailsInclude                rubyInclude
  hi def link railsMethod                     Function
  hi def link erubyRailsHelperMethod          erubyRailsMethod
  hi def link erubyRailsRenderMethod          erubyRailsMethod
  hi def link erubyRailsMethod                railsMethod
  hi def link yamlRailsDelimiter              Delimiter
  hi def link yamlRailsMethod                 railsMethod
  hi def link yamlRailsComment                Comment
endfunction

function! s:RailslogSyntax()
  syn match   railslogRender      '^\s*\<\%(Processing\|Rendering\|Rendered\|Redirected\|Completed\)\>'
  syn match   railslogComment     '^\s*# .*'
  syn match   railslogModel       '^\s*\u\%(\w\|:\)* \%(Load\%( Including Associations\| IDs For Limited Eager Loading\)\=\|Columns\|Count\|Update\|Destroy\|Delete all\)\>' skipwhite nextgroup=railslogModelNum
  syn match   railslogModel       '^\s*SQL\>' skipwhite nextgroup=railslogModelNum
  syn region  railslogModelNum    start='(' end=')' contains=railslogNumber contained skipwhite nextgroup=railslogSQL
  syn match   railslogSQL         '\u.*$' contained
  " Destroy generates multiline SQL, ugh
  syn match   railslogSQL         '^ WHERE .*$'
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
" Navigation {{{1

function! s:BufNavCommands()
  silent exe "command! -bar -buffer -nargs=? Rcd :cd ".s:rp()."/<args>"
  silent exe "command! -bar -buffer -nargs=? Rlcd :lcd ".s:rp()."/<args>"
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rfind :call s:Find(<bang>0,<count>,"",<f-args>)
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rsfind :call s:Find(<bang>0,<count>,"s",<f-args>)
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rsplitfind :call s:Find(<bang>0,<count>,"s",<f-args>)
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rvsfind :call s:Find(<bang>0,<count>,"vert s",<f-args>)
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rvsplitfind :call s:Find(<bang>0,<count>,"vert s",<f-args>)
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rtabfind :call s:Find(<bang>0,<count>,"tab",<f-args>)
  command! -buffer -bar -nargs=0 Ralternate :call s:warn('Use :A instead')|call s:Alternate(<bang>0,"find")
  if g:rails_avim_commands
    command! -buffer -bar -nargs=0 A  :call s:Alternate(<bang>0,"find")
    command! -buffer -bar -nargs=0 AS :call s:Alternate(<bang>0,"sfind")
    command! -buffer -bar -nargs=0 AV :call s:Alternate(<bang>0,"vert sfind")
    command! -buffer -bar -nargs=0 AT :call s:Alternate(<bang>0,"tabfind")
    command! -buffer -bar -nargs=0 AN :call s:Related(<bang>0,"find")
    command! -buffer -bar -nargs=0 R  :call s:Related(<bang>0,"find")
    command! -buffer -bar -nargs=0 RS :call s:Related(<bang>0,"sfind")
    command! -buffer -bar -nargs=0 RV :call s:Related(<bang>0,"vert sfind")
    command! -buffer -bar -nargs=0 RT :call s:Related(<bang>0,"tabfind")
    command! -buffer -bar -nargs=0 RN :call s:Alternate(<bang>0,"find")
  endif
endfunction

function! s:Find(bang,count,arg,...)
  let str = ""
  if a:0
    let i = 1
    while i < a:0
      let str = str . s:escarg(a:{i}) . " "
      let i = i + 1
    endwhile
    let file = s:RailsIncludefind(a:{i},1)
  else
    "let file = s:RailsIncludefind(expand("<cfile>"),1)
    let file = s:RailsFind()
  endif
  exe (a:count==1?'' : a:count).a:arg."find ".str.s:escarg(file)
endfunction

function! s:FindList(ArgLead, CmdLine, CursorPos)
  if exists("*UserFileComplete") " genutils.vim
    return UserFileComplete(s:RailsIncludefind(a:ArgLead), a:CmdLine, a:CursorPos, 1, &path)
  else
    return ""
  endif
endfunction

function! s:InitRuby()
  "if has("ruby") && ! exists("s:ruby_initialized")
    "let s:ruby_initialized = 1
    " Is there a drawback to doing this?
    "        ruby require "rubygems" rescue nil
    "        ruby require "active_support" rescue nil
  "endif
endfunction

function! RailsBalloonexpr()
  if executable('ri')
    let line = getline(v:beval_lnum)
    let b = matchstr(strpart(line,0,v:beval_col),'\%(\w\|[:.]\)*$')
    let a = s:gsub(matchstr(strpart(line,v:beval_col),'^\w*\%([?!]\|\s*=\)\?'),'\s\+','')
    let str = b.a
    let before = strpart(line,0,v:beval_col-strlen(b))
    let after  = strpart(line,v:beval_col+strlen(a))
    if str =~ '^\.'
      let str = s:gsub(str,'^\.','#')
      if before =~ '\]\s*$'
        let str = 'Array'.str
      elseif before =~ '}\s*$'
        let str = 'Hash'.str
      elseif before =~ "[\"'`]\\s*$" || before =~ '\$\d\+\s*$'
        let str = 'String'.str
      elseif before =~ '\$\d\+\.\d\+\s*$'
        let str = 'Float'.str
      elseif before =~ '\$\d\+\s*$'
        let str = 'Integer'.str
      elseif before =~ '/\s*$'
        let str = 'Regexp'.str
      else
        let str = s:sub(str,'^#','.')
      endif
    endif
    let str = s:sub(str,'.*\.\s*to_f\s*\.\s*','Float#')
    let str = s:sub(str,'.*\.\s*to_i\%(nt\)\=\s*\.\s*','Integer#')
    let str = s:sub(str,'.*\.\s*to_s\%(tr\)\=\s*\.\s*','String#')
    let str = s:sub(str,'.*\.\s*to_sym\s*\.\s*','Symbol#')
    let str = s:sub(str,'.*\.\s*to_a\%(ry\)\=\s*\.\s*','Array#')
    let str = s:sub(str,'.*\.\s*to_proc\s*\.\s*','Proc#')
    if str !~ '^\u'
      return ""
    endif
    silent! let res = s:sub(system("ri ".s:rquote(str)),'\n$','')
    if res =~ '^Nothing known about'
      return ''
    endif
    return res
  else
    return ""
  endif
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
  let line = s:sub(line,'^\(.\{'.col(".").'\}\).*','\1')
  let line = s:sub(line,'\([:"'."'".']\|%[qQ]\=[[({<]\)\=\f*$','')
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
    return s:sub(res,a:pat,a:repl)
  else
    return ""
  endif
endfunction

function! s:findamethod(func,repl)
  return s:findit('\s*\<\%('.a:func.'\)\s*(\=\s*[:'."'".'"]\(\f\+\)\>.\=',a:repl)
endfunction

function! s:findasymbol(sym,repl)
  return s:findit('\s*:\%('.a:sym.'\)\s*=>\s*(\=\s*[:'."'".'"]\(\f\+\)\>.\=',a:repl)
endfunction

function! s:findfromview(func,repl)
  return s:findit('\s*\%(<%=\=\)\=\s*\<\%('.a:func.'\)\s*(\=\s*[:'."'".'"]\(\f\+\)\>['."'".'"]\=\s*\%(%>\s*\)\=',a:repl)
endfunction

function! s:RailsFind()
  " UGH
  let res = s:findamethod('belongs_to\|has_one\|composed_of','app/models/\1')
  if res != ""|return res|endif
  let res = s:singularize(s:findamethod('has_many\|has_and_belongs_to_many','app/models/\1'))
  if res != ""|return res|endif
  let res = s:singularize(s:findamethod('create_table\|drop_table\|add_column\|rename_column\|remove_column\|add_index','app/models/\1'))
  if res != ""|return res|endif
  let res = s:singularize(s:findasymbol('through','app/models/\1'))
  if res != ""|return res|endif
  let res = s:findamethod('fixtures','test/fixtures/\1')
  if res != ""|return res|endif
  let res = s:findamethod('layout','app/views/layouts/\1')
  if res != ""|return res|endif
  let res = s:findasymbol('layout','app/views/layouts/\1')
  if res != ""|return res|endif
  let res = s:findamethod('helper','app/helpers/\1_helper')
  if res != ""|return res|endif
  let res = s:findasymbol('controller','app/controllers/\1_controller')
  if res != ""|return res|endif
  let res = s:findasymbol('action','\1')
  if res != ""|return res|endif
  let res = s:sub(s:findasymbol('partial','\1'),'\k\+$','_&')
  if res != ""|return res|endif
  let res = s:sub(s:findfromview('render\s*(\=\s*:partial\s\+=>\s*','\1'),'\k\+$','_&')
  if res != ""|return res|endif
  let res = s:findamethod('render\s*:\%(template\|action\)\s\+=>\s*','\1')
  if res != ""|return res|endif
  let res = s:findamethod('redirect_to\s*(\=\s*:action\s\+=>\s*','\1')
  if res != ""|return res|endif
  let res = s:findfromview('stylesheet_link_tag','public/stylesheets/\1')
  if res != ""|return res|endif
  let res = s:sub(s:findfromview('javascript_include_tag','public/javascripts/\1'),'/defaults$','/application')
  if res != ""|return res|endif
  if RailsFileType() =~ '^controller\>'
    let res = s:findit('\s*\<def\s\+\(\k\+\)\>(\=',s:sub(s:sub(RailsFilePath(),'/controllers/','/views/'),'_controller\.rb$','').'/\1')
    if res != ""|return res|endif
  endif
  let isf_keep = &isfname
  set isfname=@,48-57,/,-,_,: ",\",'
  " FIXME: grab visual selection in visual mode
  let cfile = expand("<cfile>")
  let res = s:RailsIncludefind(cfile,1)
  let &isfname = isf_keep
  return res
endfunction

function! s:underscore(str)
  let str = s:gsub(a:str,'::','/')
  let str = s:gsub(str,'\(\u\+\)\(\u\l\)','\1_\2')
  let str = s:gsub(str,'\(\l\|\d\)\(\u\)','\1_\2')
  let str = s:gsub(str,'-','_')
  let str = tolower(str)
  return str
endfunction

function! s:RailsIncludefind(str,...)
  if a:str == "ApplicationController"
    return "controllers/application.rb"
  elseif a:str == "Test::Unit::TestCase"
    return "test/unit/testcase.rb"
  elseif a:str == "<%="
    " Probably a silly idea
    return "action_view.rb"
  endif
  let g:mymode = mode()
  let str = a:str
  if a:0 == 1
    " Get the text before the filename under the cursor.
    " We'll cheat and peak at this in a bit
    let line = s:linepeak()
    let line = s:sub(line,'\([:"'."'".']\|%[qQ]\=[[({<]\)\=\f*$','')
  else
    let line = ""
  endif
  let str = s:sub(str,'^\s*','')
  let str = s:sub(str,'\s*$','')
  let str = s:sub(str,'^[:@]','')
  "let str = s:sub(str,"\\([\"']\\)\\(.*\\)\\1",'\2')
  let str = s:gsub(str,"[\"']",'')
  if line =~ '\<\(require\|load\)\s*(\s*$'
    return str
  endif
  let str = s:underscore(str)
  let fpat = '\(\s*\%("\f*"\|:\f*\|'."'\\f*'".'\)\s*,\s*\)*'
  if a:str =~ '\u'
    " Classes should always be in .rb files
    let str = str . '.rb'
  elseif line =~ '\(:partial\|"partial"\|'."'partial'".'\)\s*=>\s*'
    let str = s:sub(str,'\([^/]\+\)$','_\1')
    let str = s:sub(str,'^/','views/')
  elseif line =~ '\<layout\s*(\=\s*' || line =~ '\(:layout\|"layout"\|'."'layout'".'\)\s*=>\s*'
    let str = s:sub(str,'^/\=','views/layouts/')
  elseif line =~ '\(:controller\|"controller"\|'."'controller'".'\)\s*=>\s*'
    let str = 'controllers/'.str.'_controller.rb'
  elseif line =~ '\<helper\s*(\=\s*'
    let str = 'helpers/'.str.'_helper.rb'
  elseif line =~ '\<fixtures\s*(\='.fpat
    let str = s:sub(str,'^/\@!','test/fixtures/')
  elseif line =~ '\<stylesheet_\(link_tag\|path\)\s*(\='.fpat
    let str = s:sub(str,'^/\@!','/stylesheets/')
    let str = 'public'.s:sub(str,'^[^.]*$','&.css')
  elseif line =~ '\<javascript_\(include_tag\|path\)\s*(\='.fpat
    if str == "defaults"
      let str = "application"
    endif
    let str = s:sub(str,'^/\@!','/javascripts/')
    let str = 'public'.s:sub(str,'^[^.]*$','&.js')
  elseif line =~ '\<\(has_one\|belongs_to\)\s*(\=\s*'
    let str = 'models/'.str.'.rb'
  elseif line =~ '\<has_\(and_belongs_to_\)\=many\s*(\=\s*'
    let str = 'models/'.s:singularize(str).'.rb'
  elseif line =~ '\<def\s\+' && expand("%:t") =~ '_controller\.rb'
    let str = s:sub(s:sub(RailsFilePath(),'/controllers/','/views/'),'_controller\.rb$','/'.str)
    "let str = s:sub(expand("%:p"),'.*[\/]app[\/]controllers[\/]\(.\{-\}\)_controller.rb','views/\1').'/'.str
    if filereadable(str.".rhtml")
      let str = str . ".rhtml"
    elseif filereadable(str.".rxml")
      let str = str . ".rxml"
    elseif filereadable(str.".rjs")
      let str = str . ".rjs"
    endif
  else
    " If we made it this far, we'll risk making it singular.
    let str = s:singularize(str)
    let str = s:sub(str,'_id$','')
  endif
  if str =~ '^/' && !filereadable(str)
    let str = s:sub(str,'^/','')
  endif
  return str
endfunction

function! s:singularize(word)
  " Probably not worth it to be as comprehensive as Rails but we can
  " still hit the common cases.
  let word = a:word
  if word =~? '\.js$'
    return word
  endif
  let word = s:sub(word,'eople$','erson')
  let word = s:sub(word,'[aeio]\@<!ies$','ys')
  let word = s:sub(word,'xe[ns]$','xs')
  let word = s:sub(word,'ves$','fs')
  let word = s:sub(word,'ss\%(es\)\=$','sss')
  let word = s:sub(word,'s$','')
  return word
endfunction

function! s:Alternate(bang,cmd)
  let cmd = a:cmd.(a:bang?"!":"")
  let f = RailsFilePath()
  let t = RailsFileType()
  if f =~ '\<config/environments/'
    exe cmd." config/environment.rb"
  elseif f == 'README'
    exe cmd." config/database.yml"
  elseif f =~ '\<config/database\.yml$'   | exe cmd." config/routes.rb"
  elseif f =~ '\<config/routes\.rb$'      | exe cmd." config/environment.rb"
  elseif f =~ '\<config/environment\.rb$' | exe cmd." config/database.yml"
  elseif f =~ '\<db/migrate/\d\d\d_'
    let num = matchstr(f,'\<db/migrate/0*\zs\d\+\ze_')-1
    if num
      call s:Migration(0,cmd,num)
    else
      exe cmd." db/schema.rb"
    endif
  elseif f =~ '\<application\.js$'
    exe cmd." app/helpers/application_helper.rb"
  elseif t =~ '^js\>'
    exe cmd." public/javascripts/application.js"
  elseif f =~ '\<db/schema\.rb$'
    call s:Migration(0,cmd,"")
  elseif t =~ '^view\>'
    if t =~ '\<layout\>'
      let dest = fnamemodify(f,':r:s?/layouts\>??').'/layout'
      echo dest
    else
      let dest = f
    endif
    " Go to the helper, controller, or model
    let helper     = fnamemodify(dest,":h:s?/views/?/helpers/?")."_helper.rb"
    let controller = fnamemodify(dest,":h:s?/views/?/controllers/?")."_controller.rb"
    let model      = fnamemodify(dest,":h:s?/views/?/models/?").".rb"
    if filereadable(b:rails_root."/".helper)
      " Would it be better to skip the helper and go straight to the
      " controller?
      exe cmd." ".s:escarg(helper)
    elseif filereadable(b:rails_root."/".controller)
      let jumpto = expand("%:t:r")
      exe cmd." ".s:escarg(controller)
      exe "silent! djump ".jumpto
    elseif filereadable(b:rails_root."/".model)
      exe cmd." ".s:escarg(model)
    else
      exe cmd." ".s:escarg(helper)
    endif
  elseif t =~ '^controller-api\>'
    let api = s:sub(s:sub(f,'/controllers/','/apis/'),'_controller\.rb$','_api.rb')
    exe cmd." ".s:escarg(api)
  elseif t =~ '^helper\>'
    let controller = s:sub(s:sub(f,'/helpers/','/controllers/'),'_helper\.rb$','_controller.rb')
    let controller =s:sub(controller,'application_controller','application')
    exe cmd." ".s:escarg(controller)
  elseif t =~ '\<fixtures\>'
    let file = s:singularize(expand("%:t:r")).'_test.rb'
    exe cmd." ".s:escarg(file)
  else
    let file = fnamemodify(f,":t:r")
    if file =~ '_test$'
      exe cmd." ".s:escarg(s:sub(file,'_test$','.rb'))
    else
      exe cmd." ".s:escarg(file).'_test'
    endif
  endif
endfunction

function! s:Related(bang,cmd)
  let cmd = a:cmd.(a:bang?"!":"")
  let f = RailsFilePath()
  let t = RailsFileType()
  if f =~ '\<config/environments/'
    exe cmd." config/environment.rb"
  elseif f == 'README'
    exe cmd." config/database.yml"
  elseif f =~ '\<config/database\.yml$'   | exe cmd." config/environment.rb"
  elseif f =~ '\<config/routes\.rb$'      | exe cmd." config/database.yml"
  elseif f =~ '\<config/environment\.rb$' | exe cmd." config/routes.rb"
  elseif f =~ '\<db/migrate/\d\d\d_'
    let num = matchstr(f,'\<db/migrate/0*\zs\d\+\ze_')+1
    call s:Migration(0,cmd,num)
  elseif t =~ '^test\>'
    return s:error('Use :Rake instead')
    "Rake
  elseif f =~ '\<application\.js$'
    exe cmd." app/helpers/application_helper.rb"
  elseif t =~ '^js\>'
    exe cmd." public/javascripts/application.js"
  elseif t =~ '^view-layout\>'
    exe cmd." ".s:sub(s:sub(s:sub(RailsFilePath(),'/views/','/controllers/'),'/layouts/\(\k\+\)\..*$','/\1_controller.rb'),'application_controller\.rb$','application.rb')
  elseif t=~ '^view-partial\>'
    call s:warn("No related file is defined")
  elseif t =~ '^view\>'
    exe cmd." ".s:sub(s:sub(RailsFilePath(),'/views/','/controllers/'),'/\(\k\+\)\..*$','_controller|silent! djump \1')
  elseif t =~ '^controller-api\>'
    exe cmd." ".s:sub(s:sub(RailsFilePath(),'/controllers/','/apis/'),'_controller\.rb$','_api.rb')
  elseif t =~ '^controller\>'
    if s:lastmethod() != ""
      exe cmd." ".s:sub(s:sub(s:sub(RailsFilePath(),'/application\.rb$','/shared_controller.rb'),'/controllers/','/views/'),'_controller\.rb$','/'.s:lastmethod())
    else
      exe cmd." ".s:sub(s:sub(RailsFilePath(),'/controllers/','/helpers/'),'\%(_controller\)\=\.rb$','_helper.rb')
    endif
  elseif t=~ '^helper\>'
      exe cmd." ".s:sub(s:sub(RailsFilePath(),'/helpers/','/views/layouts/'),'\%(_helper\)\=\.rb$','')
  elseif t =~ '^model-ar\>'
    call s:Migration(0,cmd,'create_'.s:sub(expand('%:t:r'),'y$','ie').'s')
  elseif t =~ '^api\>'
    exe cmd." ".s:sub(s:sub(RailsFilePath(),'/apis/','/controllers/'),'_api\.rb$','_controller.rb')
  elseif f =~ '\<db/schema\.rb$'
    call s:Migration(0,cmd,"1")
  else
    call s:warn("No related file is defined")
  endif
endfunction

" }}}1
" Partials {{{1

function! s:MakePartial(bang,...) range abort
  if a:0 == 0 || a:0 > 1
    return s:error("Incorrect number of arguments")
  endif
  if a:1 =~ '[^a-z0-9_/]'
    return s:error("Invalid partial name")
  endif
  let file = a:1
  let first = a:firstline
  let last = a:lastline
  let range = first.",".last
  let curdir = expand("%:p:h")
  let dir = fnamemodify(file,":h")
  let fname = fnamemodify(file,":t")
  if fnamemodify(fname,":e") == ""
    let name = fname
    let fname = fname.".".expand("%:e")
  else
    let name = fnamemodify(name,":r")
  endif
  let var = "@".name
  let collection = ""
  if dir =~ '^/'
    let out = (RailsRoot()).dir."/_".fname
  elseif dir == ""
    let out = (curdir)."/_".fname
  elseif isdirectory(curdir."/".dir)
    let out = (curdir)."/".dir."/_".fname
  else
    let out = (RailsRoot())."/app/views/".dir."/_".fname
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
  if expand("%:e") == "rhtml"
    let erub1 = '<%\s*'
    let erub2 = '\s*-\=%>'
  else
    let erub1 = ''
    let erub2 = ''
  endif
  let spaces = matchstr(getline(first),"^ *")
  if getline(last+1) =~ '^\s*'.erub1.'end'.erub2.'\s*$'
    let fspaces = matchstr(getline(last+1),"^ *")
    if getline(first-1) =~ '^'.fspaces.erub1.'for\s\+\(\k\+\)\s\+in\s\+\([^ %>]\+\)'.erub2.'\s*$'
      let collection = s:sub(getline(first-1),'^'.fspaces.erub1.'for\s\+\(\k\+\)\s\+in\s\+\([^ >]\+\)'.erub2.'\s*$','\1>\2')
    elseif getline(first-1) =~ '^'.fspaces.erub1.'\([^ %>]\+\)\.each\s\+do\s\+|\s*\(\k\+\)\s*|'.erub2.'\s*$'
      let collection = s:sub(getline(first-1),'^'.fspaces.erub1.'\([^ %>]\+\)\.each\s\+do\s\+|\s*\(\k\+\)\s*|'.erub2.'\s*$','\2>\1')
    endif
    if collection != ''
      let var = matchstr(collection,'^\k\+')
      let collection = s:sub(collection,'^\k\+>','')
      let first = first - 1
      let last = last + 1
    endif
  else
    let fspaces = spaces
  endif
  "silent exe range."write ".out
  let renderstr = "render :partial => '".fnamemodify(file,":r")."'"
  if collection != ""
    let renderstr = renderstr.", :collection => ".collection
  elseif "@".name != var
    let renderstr = renderstr.", :object => ".var
  endif
  if expand("%:e") == "rhtml"
    let renderstr = "<%= ".renderstr." %>"
  endif
  let buf = @@
  silent exe range."yank"
  let partial = @@
  let @@ = buf
  silent exe "norm :".first.",".last."change\<CR>".fspaces.renderstr."\<CR>.\<CR>"
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
  exe "silent file ".s:escarg(fnamemodify(out,':~:.'))
  let &ft = ft
  let @@ = partial
  silent put
  0delete
  let @@ = buf
  if spaces != ""
    silent! exe '%sub/^'.spaces.'//'
  endif
  silent! exe '%sub?\%(\w\|[@:]\)\@<!'.var.'\>?'.name.'?g'
  1
  call s:Detect(out)
  if exists("l:partial_warn")
    call s:warn("Warning: partial exists!")
  endif
endfunction

" }}}1
" Statusline {{{1
function! s:InitStatusline()
  if &statusline !~ 'Rails'
    let &statusline=substitute(&statusline,'\C%Y','%Y%{RailsSTATUSLINE()}','')
    let &statusline=substitute(&statusline,'\C%y','%y%{RailsStatusline()}','')
  endif
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

function! s:leaderunmap(key,...)
  silent! exe "unmap <buffer> ".g:rails_leader.a:key
endfunction

function! s:leadermap(key,mapping)
  exe "map <buffer> ".g:rails_leader.a:key." ".a:mapping
endfunction

function! s:BufMappings()
  map <buffer> <silent> <Plug>RailsAlternate :A<CR>
  map <buffer> <silent> <Plug>RailsFind      :Rfind<CR>
  map <buffer> <silent> <Plug>RailsSplitFind :Rsfind<CR>
  map <buffer> <silent> <Plug>RailsVSplitFind :Rvsfind<CR>
  map <buffer> <silent> <Plug>RailsTabFind   :Rtabfind<CR>
  map <buffer> <silent> <Plug>RailsRelated   :call <SID>Related(0,"find")<CR>
  if g:rails_mappings
    " Unmap so hasmapto doesn't get confused by stale bindings
    call s:leaderunmap('f','<Plug>RailsFind')
    call s:leaderunmap('a','<Plug>RailsAlternate')
    call s:leaderunmap('m','<Plug>RailsRelated')
    silent! unmap <buffer> <Plug>RailsMagicM
    if !hasmapto("<Plug>RailsFind")
      nmap <buffer> gf              <Plug>RailsFind
    endif
    if !hasmapto("<Plug>RailsSplitFind")
      nmap <buffer> <C-W>f          <Plug>RailsSplitFind
    endif
    if !hasmapto("<Plug>RailsTabFind")
      nmap <buffer> <C-W>gf         <Plug>RailsTabFind
    endif
    " Lets see if anyone complains about these next two.
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
    map <buffer> <silent> <Plug>RailsMagicM    <Plug>RailsRelated
    "map <buffer> <LocalLeader>rf <Plug>RailsFind
    "map <buffer> <LocalLeader>ra <Plug>RailsAlternate
    "map <buffer> <LocalLeader>rm <Plug>RailsRelated
    call s:leadermap('f','<Plug>RailsFind')
    call s:leadermap('a','<Plug>RailsAlternate')
    call s:leadermap('m','<Plug>RailsRelated')
  endif
endfunction

" }}}1
" Menus {{{1

function! s:CreateMenus() abort
  if exists("g:rails_installed_menu") && g:rails_installed_menu != ""
    exe "aunmenu ".s:gsub(g:rails_installed_menu,'&','')
    unlet g:rails_installed_menu
  endif
  if has("menu") && (exists("g:did_install_default_menus") || exists("$CREAM")) && g:rails_menu
    if g:rails_menu > 1
      let g:rails_installed_menu = '&Rails'
    else
      let g:rails_installed_menu = '&Plugin.&Rails'
    endif
    if exists("$CREAM")
      let menucmd = '87anoremenu <script> '
      exe menucmd.g:rails_installed_menu.'.&Related\ file\	:R\ /\ Alt+] :R<CR>'
      exe menucmd.g:rails_installed_menu.'.&Alternate\ file\	:A\ /\ Alt+[ :A<CR>'
      exe menucmd.g:rails_installed_menu.'.&File\ under\ cursor\	Ctrl+Enter :Rfind<CR>'
    else
      let menucmd = 'anoremenu <script> '
      "exe menucmd.g:rails_installed_menu.'.&Related\ file\	:R :R<CR>'
      "exe menucmd.g:rails_installed_menu.'.&Alternate\ file\	:A :A<CR>'
      exe menucmd.g:rails_installed_menu.'.&Related\ file\	:R\ /\ ]f :R<CR>'
      exe menucmd.g:rails_installed_menu.'.&Alternate\ file\	:A\ /\ [f :A<CR>'
      exe menucmd.g:rails_installed_menu.'.&File\ under\ cursor\	gf :Rfind<CR>'
    endif
    exe menucmd.g:rails_installed_menu.'.&Other\ files.Application\ &Controller :find app/controllers/application.rb<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.Application\ &Helper :find app/helpers/application_helper.rb<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.Application\ &Javascript :find public/javascripts/application.js<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.Application\ &Layout :Rlayout application<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.Application\ &README :find doc/README_FOR_APP<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.&Environment :find config/environment.rb<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.&Database\ Configuration :find config/database.yml<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.Database\ &Schema :call <SID>findschema()<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.R&outes :find config/routes.rb<CR>'
    exe menucmd.g:rails_installed_menu.'.&Other\ files.&Test\ Helper :find test/test_helper.rb<CR>'
    exe menucmd.g:rails_installed_menu.'.-FSep- :'
    exe menucmd.g:rails_installed_menu.'.Ra&ke\	:Rake :Rake<CR>'
    let tasks = s:raketasks()
    while tasks != ''
      let task = matchstr(tasks,'.\{-\}\ze\%(\n\|$\)')
      let tasks = s:sub(tasks,'.\{-\}\%(\n\|$\)','')
      exe menucmd.g:rails_installed_menu.'.Rake\ &tasks\	:Rake.'.s:sub(s:sub(task,'^[^:]*$','&:all'),':','.').' :Rake '.task.'<CR>'
    endwhile
    let tasks = s:generators()
    while tasks != ''
      let task = matchstr(tasks,'.\{-\}\ze\%(\n\|$\)')
      let tasks = s:sub(tasks,'.\{-\}\%(\n\|$\)','')
      exe menucmd.'<silent> '.g:rails_installed_menu.'.&Generate\	:Rgen.'.s:gsub(task,'_','\\ ').' :call <SID>menuprompt("Rgenerate '.task.'","Arguments for script/generate '.task.': ")<CR>'
      exe menucmd.'<silent> '.g:rails_installed_menu.'.&Destroy\	:Rdestroy.'.s:gsub(task,'_','\\ ').' :call <SID>menuprompt("Rdestroy '.task.'","Arguments for script/destroy '.task.': ")<CR>'
    endwhile
    exe menucmd.g:rails_installed_menu.'.&Server\	:Rserver.&Start\	:Rserver :Rserver<CR>'
    exe menucmd.g:rails_installed_menu.'.&Server\	:Rserver.&Force\ start\	:Rserver! :Rserver!<CR>'
    exe menucmd.g:rails_installed_menu.'.&Server\	:Rserver.&Kill\	:Rserver!\ - :Rserver! -<CR>'
    exe menucmd.g:rails_installed_menu.'.&Console\	:Rconsole :Rconsole<CR>'
    exe menucmd.g:rails_installed_menu.'.&Breakpointer\	:Rbreak :Rbreakpointer<CR>'
    exe menucmd.g:rails_installed_menu.'.&Preview\	:Rpreview :Rpreview<CR>'
    exe menucmd.g:rails_installed_menu.'.&Log\	:Rlog :Rlog<CR>'
    exe s:sub(menucmd,'anoremenu','vnoremenu').' <silent> '.g:rails_installed_menu.'.E&xtract\ as\ partial\	:Rpartial :call <SID>menuprompt("'."'".'<,'."'".'>Rpartial","Partial name (e.g., template or /controller/template): ")<CR>'
    exe menucmd.'         '.g:rails_installed_menu.'.-HSep- :'
    exe menucmd.'<silent> '.g:rails_installed_menu.'.&Help\	:help\ rails :call <SID>prephelp()<Bar>help rails<CR>'
    exe menucmd.'<silent> '.g:rails_installed_menu.'.Abo&ut :call <SID>prephelp()<Bar>help rails-about<CR>'
    let g:rails_did_menus = 1
    call s:menuBufLeave()
    if exists("b:rails_root")
      call s:menuBufEnter()
    endif
  endif
endfunction

function! s:menuBufEnter()
  if exists("g:rails_installed_menu") && g:rails_installed_menu != ""
    let menu = s:gsub(g:rails_installed_menu,'&','')
    exe 'amenu enable '.menu.'.*'
    if RailsFileType() !~ '^view\>'
      exe 'vmenu disable '.menu.'.Extract\ as\ partial'
    endif
  endif
endfunction

function! s:menuBufLeave()
  if exists("g:rails_installed_menu") && g:rails_installed_menu != ""
    let menu = s:gsub(g:rails_installed_menu,'&','')
    exe 'amenu disable '.menu.'.*'
    exe 'amenu enable  '.menu.'.Help'
    exe 'amenu enable  '.menu.'.About'
  endif
endfunction
function! s:menuprompt(vimcmd,prompt)
  let res = inputdialog(a:prompt,'','!!!')
  if res == '!!!'
    return ""
  endif
  exe a:vimcmd." ".res
endfunction

function! s:prephelp()
  let fn = fnamemodify(s:file,':h:h').'/doc/'
  if filereadable(fn.'rails.txt')
    if !filereadable(fn.'tags') || getftime(fn.'tags') <= getftime(fn.'rails.txt')
      silent! exe "helptags ".s:escarg(fn)
    endif
  endif
endfunction

function! s:findschema()
  if filereadable(RailsRoot()."/db/schema.rb")
    exe "edit ".s:ra()."/db/schema.rb"
  elseif filereadable(RailsRoot()."/db/".s:environment()."_structure.sql")
    exe "edit ".s:ra()."/db/".s:environment()."_structure.sql"
  else
    return s:error("Schema not found: try :Rake db:schema:dump")
  endif
endfunction

" }}}1
" Database {{{1

function! s:extractdbarg(str,arg)
  return matchstr("\n".a:str."\n",'\n'.a:arg.'=\zs.\{-\}\ze\n')
endfunction

function! s:BufDatabase(...)
  if (a:0 && a:1 > 1) || !exists("s:dbext_last_root")
    let s:dbext_last_root = '*'
  endif
  if (a:0 > 1 && a:2 != '')
    let env = a:2
  else
    let env = s:environment()
  endif
  " Crude caching mechanism
  if s:dbext_last_root != RailsRoot()
    if exists("g:loaded_dbext") && (g:rails_dbext + (a:0 ? a:1 : 0)) > 0
      " Ideally we would filter this through ERB but that could be insecure.
      " It might be possible to make use of taint checking.
      let cmdb = 'require %{yaml}; y = File.open(%q{'.RailsRoot().'/config/database.yml}) {|f| YAML::load(f)}; e = y[%{'
      let cmde = '}]; i=0; e=y[e] while e.respond_to?(:to_str) && (i+=1)<16; e.each{|k,v|puts k+%{=}+v if v}'
      let out = s:rubyeval(cmdb.env.cmde,'')
      let adapter = s:extractdbarg(out,'adapter')
      let s:dbext_bin = ''
      let s:dbext_integratedlogin = ''
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
      let s:dbext_type = toupper(adapter)
      let s:dbext_user = s:extractdbarg(out,'username')
      let s:dbext_passwd = s:extractdbarg(out,'password')
      let s:dbext_dbname = s:extractdbarg(out,'database')
      if s:dbext_dbname != '' && s:dbext_dbname !~ '^:' && adapter =~? '^sqlite'
        let s:dbext_dbname = RailsRoot().'/'.s:dbext_dbname
      endif
      let s:dbext_profile = ''
      let s:dbext_host = s:extractdbarg(out,'host')
      let s:dbext_port = s:extractdbarg(out,'port')
      let s:dbext_dsnname = s:extractdbarg(out,'dsn')
      if s:dbext_host =~? '^\cDBI:'
        if s:dbext_host =~? '\c\<Trusted[_ ]Connection\s*=\s*yes\>'
          let s:dbext_integratedlogin = 1
        endif
        let s:dbext_host = matchstr(s:dbext_host,'\c\<\%(Server\|Data Source\)\s*=\s*\zs[^;]*')
      endif
      let s:dbext_last_root = RailsRoot()
    endif
  endif
  if s:dbext_last_root == RailsRoot()
    silent! let b:dbext_type    = s:dbext_type
    silent! let b:dbext_profile = s:dbext_profile
    silent! let b:dbext_bin     = s:dbext_bin
    silent! let b:dbext_user    = s:dbext_user
    silent! let b:dbext_passwd  = s:dbext_passwd
    silent! let b:dbext_dbname  = s:dbext_dbname
    silent! let b:dbext_host    = s:dbext_host
    silent! let b:dbext_port    = s:dbext_port
    silent! let b:dbext_dsnname = s:dbext_dsnname
    silent! let b:dbext_integratedlogin = s:dbext_integratedlogin
  endif
  if a:0 >= 3 && a:3 && exists(":Create")
    if exists("b:dbext_dbname") && exists("b:dbext_type") && b:dbext_type !~? 'sqlite'
      let db = b:dbext_dbname
      let b:dbext_dbname = ''
      exe "Create database ".db
      let b:dbext_dbname = db
    endif
  endif
endfunction

" }}}1
" Abbreviations {{{1

function! s:RailsSelectiveExpand(pat,good,default,...)
  if a:0 > 0
    let nd = a:1
  else
    let nd = ""
  endif
  let c = nr2char(getchar(0))
  "let good = s:gsub(a:good,'\\<Esc>',"\<Esc>")
  let good = a:good
  if c == "" || c == "\t"
    return good.(a:0 ? " ".a:1 : '')
  elseif c =~ a:pat
    return good.c.(a:0 ? a:1 : '')
  else
    return a:default.c
  endif
endfunction

function! s:DiscretionaryComma()
  let c = nr2char(getchar(0))
  if c =~ '[\r,;]'
    return c
  else
    return ",".c
  endif
endfunction

function! s:TheMagicC()
  let l = s:linepeak()
  if l =~ '\<find\s*\((\|:first,\|:all,\)'
    return <SID>RailsSelectiveExpand('..',':conditions => ',':c')
  elseif l =~ '\<render\s*(\=\s*:partial\s\+=>\s*'
    return <SID>RailsSelectiveExpand('..',':collection => ',':c')
  else
    return <SID>RailsSelectiveExpand('..',':controller => ',':c')
  endif
endfunction

function! s:AddSelectiveExpand(abbr,pat,expn,...)
  let pat = s:gsub(a:pat,"'","'.\"'\".'")
  let expn = s:gsub(s:gsub(a:expn,'["|]','\\&'),'<','<Lt>')
  exe "iabbr <buffer> <silent> ".a:abbr." <C-R>=<SID>RailsSelectiveExpand('".pat."',\"".expn."\",'".a:abbr.(a:0 ? "','".a:1 : '')."')<CR>"
endfunction

function! s:AddTabExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'..',a:expn)
endfunction

function! s:AddBracketExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'[[]',a:expn)
endfunction

function! s:AddColonExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,':',a:expn)
endfunction

function! s:AddParenExpand(abbr,expn,...)
  if a:0
    call s:AddSelectiveExpand(a:abbr,'(',a:expn,a:1)
  else
    call s:AddSelectiveExpand(a:abbr,'(',a:expn)
  endif
endfunction

function! s:BufAbbreviations()
  " EXPERIMENTAL.  USE AT YOUR OWN RISK
  " Some of these were cherry picked from the TextMate snippets
  if g:rails_abbreviations
    " Limit to the right filetypes.  But error on the liberal side
    if RailsFileType() =~ '^\(controller\|view\|helper\|test-functional\|test-integration\)\>'
      call s:AddBracketExpand('pa','params')
      call s:AddBracketExpand('rq','request')
      call s:AddBracketExpand('rs','response')
      call s:AddBracketExpand('se','session')
      call s:AddBracketExpand('he','headers')
      call s:AddBracketExpand('te','template')
      call s:AddBracketExpand('co','cookies')
      call s:AddBracketExpand('fl','flash')
      call s:AddParenExpand('rr','render ')
      call s:AddParenExpand('rp','render',':partial => ')
      call s:AddParenExpand('ri','render',':inline => ')
      call s:AddParenExpand('rt','render',':text => ')
      call s:AddParenExpand('rtlt','render',':layout => true, :text => ')
      call s:AddParenExpand('rl','render',':layout => ')
      call s:AddParenExpand('ra','render',':action => ')
      call s:AddParenExpand('rc','render',':controller => ')
      call s:AddParenExpand('rf','render',':file => ')
      iabbr <buffer> render_partial render :partial =>
      iabbr <buffer> render_action render :action =>
      iabbr <buffer> render_text render :text =>
      iabbr <buffer> render_file render :file =>
      iabbr <buffer> render_template render :template =>
      iabbr <buffer> <silent> render_nothing render :nothing => true<C-R>=<SID>DiscretionaryComma()<CR>
      iabbr <buffer> <silent> render_without_layout render :layout => false<C-R>=<SID>DiscretionaryComma()<CR>
    endif
    if RailsFileType() =~ '^view\>'
      call s:AddTabExpand('dotiw','distance_of_time_in_words ')
      call s:AddTabExpand('taiw','time_ago_in_words ')
    endif
    if RailsFileType() =~ '^controller\>'
      call s:AddSelectiveExpand('rn','[,\r]','render :nothing => true')
      call s:AddParenExpand('rea','redirect_to',':action => ')
      call s:AddParenExpand('rec','redirect_to',':controller => ')
    endif
    if RailsFileType() =~ '^model-ar\>' || RailsFileType() =~ '^model$'
      call s:AddParenExpand('bt','belongs_to','')
      call s:AddParenExpand('ho','has_one','')
      call s:AddParenExpand('hm','has_many','')
      call s:AddParenExpand('habtm','has_and_belongs_to_many','')
      call s:AddParenExpand('va','validates_associated','')
      call s:AddParenExpand('vb','validates_acceptance_of','')
      call s:AddParenExpand('vc','validates_confirmation_of','')
      call s:AddParenExpand('ve','validates_exclusion_of','')
      call s:AddParenExpand('vf','validates_format_of','')
      call s:AddParenExpand('vi','validates_inclusion_of','')
      call s:AddParenExpand('vl','validates_length_of','')
      call s:AddParenExpand('vn','validates_numericality_of','')
      call s:AddParenExpand('vp','validates_presence_of','')
      call s:AddParenExpand('vu','validates_uniqueness_of','')
      call s:AddParenExpand('co','composed_of','')
    endif
    if RailsFileType() =~ '^migration\>'
      call s:AddParenExpand('mrnt','rename_table','')
      call s:AddParenExpand('mcc','t.column','')
      call s:AddParenExpand('mrnc','rename_column','')
      call s:AddParenExpand('mac','add_column','')
      call s:AddParenExpand('mdt','drop_table','')
      call s:AddParenExpand('mrc','remove_column','')
      "call s:AddParenExpand('mct','create_table','')
      " ugh, stupid POS
      call s:AddTabExpand('mct','create_table "" do \<Bar>t\<Bar>\<Esc>7hi')
    endif
    if RailsFileType() =~ '^test\>'
      call s:AddParenExpand('ae','assert_equal','')
      call s:AddParenExpand('ako','assert_kind_of','')
      call s:AddParenExpand('ann','assert_not_nil','')
      call s:AddParenExpand('ar','assert_raise','')
      call s:AddParenExpand('art','assert_redirected_to','')
      call s:AddParenExpand('are','assert_response','')
    endif
    iabbr <buffer> <silent> :c <C-R>=<SID>TheMagicC()<CR>
    call s:AddTabExpand(':a',':action => ')
    call s:AddTabExpand(':i',':id => ')
    call s:AddTabExpand(':o',':object => ')
    call s:AddTabExpand(':p',':partial => ')
    call s:AddParenExpand('logd','logger.debug','')
    call s:AddParenExpand('logi','logger.info','')
    call s:AddParenExpand('logw','logger.warn','')
    call s:AddParenExpand('loge','logger.error','')
    call s:AddParenExpand('logf','logger.fatal','')
    call s:AddParenExpand('fi','find','')
    call s:AddColonExpand('AR','ActiveRecord')
    call s:AddColonExpand('AV','ActionView')
    call s:AddColonExpand('AC','ActionController')
    call s:AddColonExpand('AS','ActiveSupport')
    call s:AddColonExpand('AM','ActionMailer')
    call s:AddColonExpand('AWS','ActionWebService')
  endif
endfunction
" }}}1
" Modelines {{{1

function! s:BufModelines()
  if !g:rails_modelines
    return
  endif
  let lines = getline(1)."\n".getline(2)."\n".getline(3)."\n".getline("$")."\n"
  let pat = '\s\+\zs.\{-\}\ze\%(\n\|\s\s\|#{\@!\|%>\|-->\|$\)'
  let mat = matchstr(lines,'\<Rset'.pat)
  let mat = s:sub(mat,'\s\+$','')
  let mat = s:gsub(mat,'|','\\|')
  if mat != ''
    silent! exe "Rset ".mat
  endif
endfunction

" }}}1
" Initialization {{{1

function! s:InitPlugin()
  call s:InitConfig()
  if g:rails_statusline
    call s:InitStatusline()
  endif
  if has("autocmd") && g:rails_level >= 0
    augroup railsPluginDetect
      autocmd!
      autocmd BufNewFile,BufRead * call s:Detect(expand("<afile>:p"))
      autocmd BufEnter * call s:BufEnter()
      autocmd BufLeave * call s:BufLeave()
      autocmd VimEnter * if expand("<amatch>") == "" && !exists("b:rails_root") | call s:Detect(getcwd()) | call s:BufEnter() | endif
      autocmd BufWritePost */config/database.yml let s:dbext_last_root = "*" " Force reload
      autocmd BufWritePost,BufReadPost * call s:breaktabs()
      autocmd BufWritePre              * call s:fixtabs()
      autocmd FileType railslog call s:RailslogSyntax()
      autocmd FileType * if exists("b:rails_root") | call s:BufSettings() | endif
      autocmd FileType netrw call s:Detect(expand("<afile>:p"))
      autocmd Syntax ruby,eruby,yaml,railslog if exists("b:rails_root") | call s:BufSyntax() | endif
      silent! autocmd QuickFixCmdPre  make* call s:QuickFixCmdPre()
      silent! autocmd QuickFixCmdPost make* call s:QuickFixCmdPost()
    augroup END
  endif
  command! -bar -bang -nargs=* -complete=dir Rails :call s:NewApp(<bang>0,<f-args>)
  call s:CreateMenus()
endfunction

function! s:Detect(filename)
  let fn = fnamemodify(a:filename,":p")
  if fn =~ '[\/]config[\/]environment\.rb$'
    return s:BufInit(strpart(fn,0,strlen(fn)-22))
  endif
  if isdirectory(fn)
    let fn = fnamemodify(fn,":s?[\/]$??")
  else
    let fn = fnamemodify(fn,':s?\(.*\)[\/][^\/]*$?\1?')
  endif
  let ofn = ""
  while fn != ofn
    if filereadable(fn . "/config/environment.rb")
      return s:BufInit(fn)
    endif
    let ofn = fn
    let fn = fnamemodify(ofn,':s?\(.*\)[\/]\(app\|components\|config\|db\|doc\|lib\|log\|public\|script\|test\|tmp\|vendor\)\($\|[\/].*$\)?\1?')
  endwhile
  return 0
endfunction

function! s:BufInit(path)
  let cpo_save = &cpo
  set cpo&vim
  "call s:InitRuby()
  let b:rails_root = a:path
  if g:rails_level > 0
    if &ft == "mason"
      setlocal filetype=eruby
    endif
    if &ft == "" && expand("%:e") =~ '^\%(rjs\|rxml\|rake\|mab\)$'
      setlocal filetype=ruby
    elseif &ft == "" && expand("%:e") == 'rhtml'
      setlocal filetype=eruby
    elseif &ft == "" && expand("%:e") == 'yml'
      setlocal filetype=yaml
    else
      " Activate custom syntax
      exe "setlocal syntax=".&syntax
    endif
    if expand("%:e") == "log"
      setlocal modifiable filetype=railslog
      silent! %s/\%(\e\[[0-9;]*m\|\r$\)//g
      "silent! exe "%s/\r$//"
      setlocal readonly nomodifiable noswapfile autoread foldmethod=syntax
      nnoremap <buffer> <silent> R :checktime<CR>
      nnoremap <buffer> <silent> G :checktime<Bar>$<CR>
      nnoremap <buffer> <silent> q :bwipe<CR>
      $
    endif
  endif
  call s:BufSettings()
  call s:BufCommands()
  call s:BufMappings()
  call s:BufAbbreviations()
  call s:BufDatabase()
  let t = RailsFileType()
  if t != ""
    let t = "-".t
  endif
  exe "silent doautocmd User Rails".s:gsub(t,'-','.')."."
  if filereadable(b:rails_root."/config/rails.vim")
    if exists(":sandbox")
      sandbox exe "source ".s:rp()."/config/rails.vim"
    elseif g:rails_modelines
      exe "source ".s:rp()."/config/rails.vim"
    endif
  endif
  call s:BufModelines()
  let &cpo = cpo_save
  return b:rails_root
endfunction

function! s:SetBasePath()
  let rp = s:rp()
  let t = RailsFileType()
  let oldpath = s:sub(&l:path,'^\.,','')
  if stridx(oldpath,rp) == 2
    let oldpath = ''
  endif
  let &l:path = '.,'.rp.",".rp."/app/controllers,".rp."/app,".rp."/app/models,".rp."/app/helpers,".rp."/components,".rp."/config,".rp."/lib,".rp."/vendor/plugins/*/lib,".rp."/vendor,".rp."/test/unit,".rp."/test/functional,".rp."/test/integration,".rp."/app/apis,".rp."/test,"
  if s:controller() != ''
    if RailsFilePath() =~ '\<components/'
      let &l:path = &l:path . rp . '/components/' . s:controller() . ','
    else
      let &l:path = &l:path . rp . '/app/views/' . s:controller() . ',' . rp . '/app/views,' . rp . '/public,'
    endif
  endif
  if t =~ '^log\>'
    let &l:path = &l:path . rp . '/app/views,'
  endif
  let &l:path = &l:path . oldpath
endfunction

function! s:BufSettings()
  if !exists('b:rails_root')
    return ''
  endif
  call s:SetBasePath()
  "silent compiler rubyunit
  let rp = s:rp()
  setlocal errorformat=%D(in\ %f),
        \%A\ %\\+%\\d%\\+)\ Failure:,
        \%C%.%#\ [%f:%l]:,
        \%A\ %\\+%\\d%\\+)\ Error:,
        \%CActionView::TemplateError:\ compile\ error,
        \%C%.%#/lib/gems/%\\d.%\\d/gems/%.%#,
        \%C%.%#/vendor/rails/%.%#,
        \%Z%f:%l:\ syntax\ error\\,\ %m,
        \%Z%f:%l:\ %m,
        \%Z\ %#,
        \%Z%p^,
        \%C\ %\\+On\ line\ #%l\ of\ %f,
        \%C\ \ \ \ %f:%l:%.%#,
        \%Ctest_%.%#:,
        \%CActionView::TemplateError:\ %f:%l:in\ `%.%#':\ %m,
        \%CActionView::TemplateError:\ You\ have\ a\ %m!,
        \%CNoMethodError:\ You\ have\ a\ %m!,
        \%CActionView::TemplateError:\ %m,
        \%CThe\ error\ occured\ while\ %m,
        \%C%m,
        \ActionView::TemplateError\ (%m)\ on\ line\ #%l\ of\ %f:,
        \%AActionView::TemplateError\ (compile\ error,
        \%.%#/rake_test_loader.rb:%\\d%\\+:in\ `load':\ %f:%l:\ %m,
        \%-G%.%#/lib/gems/%\\d.%\\d/gems/%.%#,
        \%-G%.%#/vendor/rails/%.%#,
        \%f:%l:\ %m,
        \%-G%.%#
  "let &l:makeprg='rake -f '.rp.'/Rakefile $*'
  setlocal makeprg=rake
  if stridx(&tags,rp) == -1
    let &l:tags = &tags . "," . rp ."/tags"
  endif
  if has("balloon_eval") && exists("+balloonexpr") && executable('ri')
    setlocal balloonexpr=RailsBalloonexpr()
  endif
  " There is no rjs/rxml filetype now, but in the future, who knows...
  if &ft == "ruby" || &ft == "eruby" || &ft == "rjs" || &ft == "rxml" || &ft == "yaml"
    " This is a strong convention in Rails, so we'll break the usual rule
    " of considering shiftwidth to be a personal preference
    setlocal sw=2 sts=2 et
    "set include=\\<\\zsAct\\f*::Base\\ze\\>\\\|^\\s*\\(require\\\|load\\)\\s\\+['\"]\\zs\\f\\+\\ze
    setlocal includeexpr=RailsIncludeexpr()
    if exists('+completefunc')
      if &completefunc == ''
        set completefunc=syntaxcomplete#Complete
      endif
    endif
  else
    " Does this cause problems in any filetypes?
    setlocal includeexpr=RailsIncludeexpr()
    setlocal suffixesadd=.rb,.rhtml,.rxml,.rjs,.mab,.css,.js,.yml,.csv,.rake,.sql,.html
  endif
  if &filetype == "ruby"
    setlocal suffixesadd=.rb,.rhtml,.rxml,.rjs,.mab,.yml,.csv,.rake,s.rb
    if expand('%:e') == 'rake'
      setlocal define=^\\s*def\\s\\+\\(self\\.\\)\\=\\\|^\\s*\\%(task\\\|file\\)\\s\\+[:'\"]
    else
      setlocal define=^\\s*def\\s\\+\\(self\\.\\)\\=
    endif
  elseif &filetype == "eruby"
    "set include=\\<\\zsAct\\f*::Base\\ze\\>\\\|^\\s*\\(require\\\|load\\)\\s\\+['\"]\\zs\\f\\+\\ze\\\|\\zs<%=\\ze
    setlocal suffixesadd=.rhtml,.rxml,.rjs,.mab,.rb,.css,.js,.html
  endif
endfunction

" }}}1

let s:file = expand('<sfile>:p')
call s:InitPlugin()

let &cpo = cpo_save

" vim:set sw=2 sts=2:
