" rails.vim - Detect a rails application
" Author:       Tim Pope <vimNOSPAM@tpope.info>
" Last Change:  2006 Jun 01
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
if exists("g:loaded_rails") && g:loaded_rails || &cp
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

function! s:rquote(str)
  " Imperfect but adequate for Ruby arguments
  if a:str =~ '^[A-Za-z0-9_/.-]\+$'
    return a:str
  else
    return "'".s:gsub(s:gsub(a:str,'\','\\'),"'","'\\\\''")."'"
  endif
endfunction

function! s:escapepath(p)
  return s:gsub(a:p,' ','\\ ')
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
  if &shellquote == ""
    let q = '"'
  else
    let q = &shellquote
  endif
  let cmd = 'ruby -e '.q.'require %{rubygems} rescue nil; require %{active_support} rescue nil; '.a:ruby.q
  "let g:rails_last_ruby_command = cmd
  let results = system(cmd)
  "let g:rails_last_ruby_result = results
  if results =~ '-e:\d'
    return def
  else
    return results
  endif
endfunction

function! s:lastmethod()
  let line = line(".")
  while line > 0 && getline(line) !~ &l:define
    let line = line -1
  endwhile
  if line
    return matchstr(getline(line),&define.'\zs\k\+')
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
  let v:warningmsg = a:str
endfunction

function! s:error(str)
  echohl ErrorMsg
  echomsg a:str
  echohl None
  let v:errmsg = a:str
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
      autocmd BufEnter * call s:SetGlobals()
      autocmd BufLeave * call s:ClearGlobals()
      autocmd FileType railslog call s:RailslogSyntax()
    augroup END
  endif
  command! -bar -bang -nargs=* -complete=dir Rails :call s:NewApp(<bang>0,<f-args>)
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

function! s:SetGlobals()
  if exists("b:rails_root")
    if g:rails_isfname
      let b:rails_restore_isfname=&isfname
      set isfname=@,48-57,/,-,_,\",',:
    endif
  endif
endfunction

function! s:ClearGlobals()
  if exists("b:rails_restore_isfname")
    let &isfname=b:rails_restore_isfname
    unlet b:rails_restore_isfname
  endif
endfunction

function! s:BufInit(path)
  call s:InitRuby()
  let b:rails_root = a:path
  let b:rails_app_path = b:rails_root
  let rp = s:escapepath(b:rails_root)
  if g:rails_level > 0
    if &ft == "mason"
      setlocal filetype=eruby
    endif
    if &ft == "" && ( expand("%:e") == "rjs" || expand("%:e") == "rxml" || expand("%:e") == "mab" )
      setlocal filetype=ruby
    endif
    if expand("%:e") == "log"
      setlocal modifiable filetype=railslog
      silent! exe "%s/\e\\[[0-9;]*m//g"
      silent! exe "%s/\r$//"
      setlocal readonly nomodifiable noswapfile autoread foldmethod=syntax
      $
    endif
    call s:BufSyntax()
    call s:BufCommands()
    call s:BufMappings()
    call s:BufAbbreviations()
    call s:SetBasePath()
    silent! compiler rubyunit
    let &l:makeprg='rake -f '.rp.'/Rakefile'
    if has("balloon_eval") && executable('ri')
      setlocal balloonexpr=RailsBalloonexpr()
    endif
    if &ft == "ruby" || &ft == "eruby" || &ft == "rjs" || &ft == "rxml"
      " This is a strong convention in Rails, so we'll break the usual rule
      " of considering shiftwidth to be a personal preference
      setlocal sw=2 sts=2 et
      "set include=\\<\\zsAct\\f*::Base\\ze\\>\\\|^\\s*\\(require\\\|load\\)\\s\\+['\"]\\zs\\f\\+\\ze
      setlocal includeexpr=RailsIncludeexpr()
      if exists('+completefunc') && &completefunc == ''
        set completefunc=syntaxcomplete#Complete
      endif
    else
      " Does this cause problems in any filetypes?
      setlocal includeexpr=RailsIncludeexpr()
      setlocal suffixesadd=.rb,.rhtml,.rxml,.rjs,.mab,.css,.js,.yml,.csv,.rake,.sql,.html
    endif
    if &filetype == "ruby"
      setlocal suffixesadd=.rb,.rhtml,.rxml,.rjs,.mab,.yml,.csv,.rake,s.rb
      setlocal define=^\\s*def\\s\\+\\(self\\.\\)\\=
    elseif &filetype == "eruby"
      "set include=\\<\\zsAct\\f*::Base\\ze\\>\\\|^\\s*\\(require\\\|load\\)\\s\\+['\"]\\zs\\f\\+\\ze\\\|\\zs<%=\\ze
      setlocal suffixesadd=.rhtml,.rxml,.rjs,.mab,.rb,.css,.js,.html
    endif
  endif
  let t = RailsFileType()
  if t != ""
    let t = "-".t
  endif
  exe "silent doautocmd User Rails".t."-"
  if filereadable(b:rails_root."/config/rails.vim") && exists(":sandbox")
    sandbox exe "source ".rp."/config/rails.vim"
  endif
  return b:rails_root
endfunction

" }}}1
" "Public" Interface {{{1

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
    elseif top =~ '\<validates_\w\+_of\>'
      let r = "model-ar"
    else
      let r = "model"
    endif
  elseif f =~ '\<app/views/layouts\>'
    let r = "view-layout-" . e
  elseif f =~ '\<\%(app/views\|components\)/.*/_\k\+\.\k\+$'
    let r = "view-partial-" . e
  elseif f =~ '\<app/views\>' || f =~ '\<components/.*/.*\.\(rhtml\|rxml\|rjs\|mab\)'
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
  elseif f =~ '\<db/migrate\>'
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
  call s:SetOptDefault("rails_avim_commands",l>2)
  call s:SetOptDefault("rails_subversion",l>3)
  call s:SetOptDefault("rails_default_file","README")
  call s:SetOptDefault("rails_default_database","")
  call s:SetOptDefault("rails_leader","<LocalLeader>r")
  call s:SetOptDefault("rails_root_url",'http://localhost:3000/')
  if l > 3
    "call s:SetOptDefault("ruby_no_identifiers",1)
    call s:SetOptDefault("rubycomplete_rails",1)
  endif
  "call s:SetOptDefault("",)
endfunction

" }}}1
" Commands {{{1

function! s:BufCommands()
  let rp = s:escapepath(b:rails_root)
  "  silent exe 'command! -buffer -complete=custom,s:ScriptComplete -nargs=+ Script :!ruby '.s:escapepath(b:rails_root.'/script/').'<args>'
  command! -buffer -bar -complete=custom,s:ScriptComplete -nargs=+ Rscript :call s:Script(<bang>0,<f-args>)
  command! -buffer -bar -complete=custom,s:ScriptComplete -nargs=+ Script :Rscript<bang> <args>
  command! -buffer -bar -complete=custom,s:ConsoleComplete -nargs=* Rconsole :Rscript console <args>
  command! -buffer -bar -complete=custom,s:GenerateComplete -nargs=* Rgenerate :call s:Generate(<bang>0,<f-args>)
  command! -buffer -bar -complete=custom,s:DestroyComplete -nargs=* Rdestroy :call s:Destroy(<bang>0,<f-args>)
  command! -buffer -bar -complete=custom,s:PluginComplete -nargs=* Rplugin :call s:Plugin(<bang>0,<f-args>)
  command! -buffer -bar -complete=custom,s:RakeComplete -nargs=? Rake :call s:Rake(<bang>0,<q-args>)
  command! -buffer -bar -complete=custom,s:PreviewComplete -nargs=? Rpreview :call s:Preview(<bang>0,<q-args>)
  command! -buffer -bar -complete=custom,s:environments -nargs=? Rlog :call s:Log(<bang>0,<q-args>)
  command! -buffer -bar -complete=custom,s:environments -nargs=* Rserver :Rscript server --daemon
  command! -buffer -nargs=1 Rrunner :call s:Script(<bang>0,"runner",<f-args>)
  command! -buffer -bar -nargs=? Rmigration :call s:Migration(<bang>0,<q-args>)
  command! -buffer -bar -nargs=* Rcontroller :call s:ControllerFunc(<bang>0,"app/controllers/","_controller.rb",<f-args>)
  command! -buffer -bar -nargs=* Rhelper :call s:ControllerFunc(<bang>0,"app/helpers/","_helper.rb",<f-args>)
  silent exe "command! -buffer -nargs=? Rcd :cd ".rp."/<args>"
  silent exe "command! -buffer -nargs=? Rlcd :lcd ".rp."/<args>"
  command! -buffer -bar -nargs=? Cd :Rcd <args>
  command! -buffer -bar -nargs=? Lcd :Rlcd <args>
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rfind :call s:Find(<bang>0,<count>,"",<f-args>)
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rsplitfind :call s:Find(<bang>0,<count>,"split",<f-args>)
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rvsplitfind :call s:Find(<bang>0,<count>,"vert split",<f-args>)
  command! -buffer -bar -complete=custom,s:FindList -nargs=* -count=1 Rtabfind :call s:Find(<bang>0,<count>,"tab",<f-args>)
  command! -buffer -bar -nargs=0 Alternate :echoerr Use :Ralternate instead
  command! -buffer -bar -nargs=0 Ralternate :call s:Alternate(<bang>0,"find")
  if g:rails_avim_commands
    command! -buffer -bar -nargs=0 A  :call s:Alternate(<bang>0,"find")
    command! -buffer -bar -nargs=0 AS :call s:Alternate(<bang>0,"sfind")
    command! -buffer -bar -nargs=0 AV :call s:Alternate(<bang>0,"vert sfind")
    command! -buffer -bar -nargs=0 AT :call s:Alternate(<bang>0,"tabfind")
    command! -buffer -bar -nargs=0 AN :call s:MagicM(<bang>0,"find")
    command! -buffer -bar -nargs=0 R  :call s:MagicM(<bang>0,"find")
    command! -buffer -bar -nargs=0 RS :call s:MagicM(<bang>0,"sfind")
    command! -buffer -bar -nargs=0 RV :call s:MagicM(<bang>0,"vert sfind")
    command! -buffer -bar -nargs=0 RT :call s:MagicM(<bang>0,"tabfind")
    command! -buffer -bar -nargs=0 RN :call s:Alternate(<bang>0,"find")
  endif
  if exists(":Project")
    command! -buffer -bar -bang -nargs=? Rproject :call s:Project(<bang>0,<q-args>)
  endif
  let ext = expand("%:e")
  if ext == "rhtml" || ext == "rxml" || ext == "rjs" || ext == "mab"
    command! -buffer -bar -nargs=? -range Rpartial :<line1>,<line2>call s:MakePartial(<bang>0,<f-args>)
  endif
endfunction

function! s:Rake(bang,arg)
  let t = RailsFileType()
  if a:arg != ''
    exe 'make '.a:arg
    return
  elseif t =~ '^test\>'
    let meth = s:lastmethod()
    if meth =~ '^test_'
      let call = " TESTOPTS=-n/".meth."/"
    else
      let call = ""
    endif
    exe "make ".s:sub(s:gsub(t,'-',':'),'unit$\|functional$','&s')." TEST=%".call
  elseif t=~ '^migration\>'
    make db:migrate
  elseif t=~ '^model\>'
    make test:units TEST=%:p:r:s?[\/]app[\/]models[\/]?/test/unit/?_test.rb
  elseif t=~ '^\<\%(controller\|helper\|view\)\>'
    make test:functionals
  else
    make
  endif
endfunction

function s:RakeComplete(A,L,P)
  return "db:fixtures:load\ndb:migrate\ndb:schema:dump\ndb:schema:load\ndb:sessions:clear\ndb:sessions:create\ndb:structure:dump\ndb:test:clone\ndb:test:clone_structure\ndb:test:prepare\ndb:test:purge\ndoc:app\ndoc:clobber_app\ndoc:clobber_plugins\ndoc:clobber_rails\ndoc:plugins\ndoc:rails\ndoc:reapp\ndoc:rerails\nlog:clear\nrails:freeze:edge\nrails:freeze:gems\nrails:unfreeze\nrails:update\nrails:update:configs\nrails:update:javascripts\nrails:update:scripts\nstats\ntest\ntest:functionals\ntest:integration\ntest:plugins\ntest:recent\ntest:uncommitted\ntest:units\ntmp:cache:clear\ntmp:clear\ntmp:create\ntmp:sessions:clear\ntmp:sockets:clear"
endfunction

function s:Preview(bang,arg)
  let root = exists("b:rails_root_url") ? b:rails_root_url : g:rails_root_url
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
  if exists(':OpenURL')
    exe 'OpenURL '.uri
  else
    exe 'pedit '.uri.(uri =~ '?' ? '' : '?')
    wincmd w
    if &filetype == ''
      setlocal filetype=xhtml
    endif
    wincmd w
  endif
endfunction

function s:PreviewComplete(A,L,P)
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
endfunction

function! s:Log(bang,arg)
  if a:arg == ""
    exe "sfind log/".s:environment().".log"
    "exe "pedit ".s:escapepath(RailsRoot())."/log/".s:environment().".log"
  else
    exe "sfind log/".a:arg.".log"
  endif
endfunction

function! s:Project(bang,arg)
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

function s:NewProject(proj,rr,fancy)
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
endfunction

function! s:Migration(bang,arg)
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
    exe "edit ".s:escapepath(migr)
  else
    return s:error("Migration not found".(a:arg=='' ? '' : ': '.a:arg))
  endif
endfunction

function! s:Find(bang,count,arg,...)
  let str = ""
  if a:0
    let i = 1
    while i < a:0
      let str = str . s:escapepath(a:{i}) . " "
      let i = i + 1
    endwhile
    let file = s:escapepath(RailsIncludefind(a:{i},1))
  else
    "let file = RailsIncludefind(expand("<cfile>"),1)
    let file = s:RailsFind()
  endif
"  echo a:count.a:arg."find ".str.s:escapepath(file)
  exe a:count.a:arg."find ".str.s:escapepath(file)
endfunction

function! s:FindList(ArgLead, CmdLine, CursorPos)
  if exists("*UserFileComplete") " genutils.vim
    return UserFileComplete(RailsIncludefind(a:ArgLead), a:CmdLine, a:CursorPos, 1, &path)
  else
    return ""
  endif
endfunction

function! s:rubyexestr(cmd)
  return "ruby -C ".s:rquote(RailsRoot())." ".a:cmd
endfunction

function! s:rubyexe(cmd)
  exe "!".s:rubyexestr(a:cmd)
  return v:shell_error
endfunction

function! s:Script(bang,cmd,...)
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:rquote(a:{c})
    let c = c + 1
  endwhile
  call s:rubyexe(s:rquote("script/".a:cmd).str)
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
    exe "edit ".s:escapepath(RailsRoot())."/".file
  endif
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
    return "controller\nintegration_test\nmailer\nmigration\nmodel\nplugin\nscaffold\nsession_migration\nweb_service"
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
  let dir = expand(dir)
  if isdirectory(fnamemodify(dir,':h')."/.svn") && g:rails_subversion
    let append = " -c"
  else
    let append = ""
  endif
  if g:rails_default_database != ""
    let append = append." -d ".g:rails_default_database
  endif
  if a:bang
    let append = append." --force"
  endif
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:rquote(expand(a:{c}))
    let c = c + 1
  endwhile
  exe "!rails".append.str
  if filereadable(dir."/".g:rails_default_file)
    exe "edit ".s:escapepath(dir)."/".g:rails_default_file
  endif
endfunction

function! s:ControllerFunc(bang,prefix,suffix,...)
  if a:0
    let c = s:sub(RailsIncludefind(a:1),'\.rb$','')
  else
    let c = s:controller()
  endif
  if c == ""
    return s:error("No controller name given")
  endif
  let cmd = "edit".(a:bang?"! ":' ').s:escapepath(RailsRoot()).'/'.a:prefix.c.a:suffix
  exe cmd
  if a:0 > 1
    exe "silent! djump ".a:2
  endif
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

" }}}1
" Syntax {{{1

function! s:BufSyntax()
  if (!exists("g:rails_syntax") || g:rails_syntax) && (exists("g:syntax_on") || exists("g:syntax_manual"))
    let t = RailsFileType()
    if !exists("s:rails_view_helpers")
      if g:rails_expensive
        let s:rails_view_helpers = s:rubyeval('require %{action_view}; puts ActionView::Helpers.constants.grep(/Helper$/).collect {|c|ActionView::Helpers.const_get c}.collect {|c| c.public_instance_methods(false)}.flatten.sort.uniq.reject {|m| m =~ /[=?]$/}.join(%{ })',"form_tag end_form_tag")
      else
        let s:rails_view_helpers = "form_tag end_form_tag"
      endif
    endif
    "let g:rails_view_helpers = s:rails_view_helpers
    let rails_view_helpers = '+\.\@<!\<\('.s:gsub(s:rails_view_helpers,'\s\+','\\|').'\)\>+'
    if &syntax == 'ruby'
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
      if t=~ '^test\>'
        syn keyword rubyRailsTestMethod add_assertion assert assert_block assert_equal assert_in_delta assert_instance_of assert_kind_of assert_match assert_nil assert_no_match assert_not_equal assert_not_nil assert_not_same assert_nothing_raised assert_nothing_thrown assert_operator assert_raise assert_respond_to assert_same assert_send assert_throws flunk fixtures use_transactional_fixtures use_instantiated_fixtures
        if t !~ '^test-unit\>'
          syn keyword rubyRailsTestControllerMethod assert_response assert_redirected_to assert_template assert_recognizes assert_generates assert_routing assert_tag assert_no_tag assert_dom_equal assert_dom_not_equal assert_valid
        endif
      endif
      syn keyword rubyRailsMethod cattr_accessor mattr_accessor
      syn keyword rubyRailsInclude require_dependency require_gem
    elseif &syntax == "eruby" && t =~ '^view\>'
      syn cluster erubyRailsRegions contains=erubyOneLiner,erubyBlock,erubyExpression
      "exe "syn match erubyRailsHelperMethod ".rails_view_helpers." contained containedin=@erubyRailsRegions"
        exe "syn keyword erubyRailsHelperMethod ".s:sub(s:rails_view_helpers,'\<select\s\+','')." contained containedin=@erubyRailsRegions"
        syn match erubyRailsHelperMethod '\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!' contained containedin=@erubyRailsRegions
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
      syn region  yamlRailsBlock	    matchgroup=yamlRailsDelimiter start="<%%\@!" end="%>" contains=@rubyTop	containedin=ALLBUT,@yamlRailsRegions
      syn region  yamlRailsExpression matchgroup=yamlRailsDelimiter start="<%="    end="%>" contains=@rubyTop	    	containedin=ALLBUT,@yamlRailsRegions
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
  hi def link rubyRailsControllerHelperMethod rubyRailsMethod
  hi def link rubyRailsControllerDeprecatedMethod rubyRailsError
  hi def link rubyRailsFilterMethod           rubyRailsMethod
  hi def link rubyRailsTestControllerMethod   rubyRailsTestMethod
  hi def link rubyRailsTestMethod             rubyRailsMethod
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

function s:RailslogSyntax()
  syn match   railslogRender      '^\s*\<\%(Processing\|Rendering\|Rendered\|Redirected\|Completed\)\>'
  syn match   railslogComment     '^\s*# .*'
  syn match   railslogModel       '^\s*\u\w* \%(Load\|Columns\)\>' skipwhite nextgroup=railslogModelNum
  syn match   railslogModel       '^\s*SQL\>' skipwhite nextgroup=railslogModelNum
  syn region  railslogModelNum    start='(' end=')' contains=railslogNumber contained skipwhite nextgroup=railslogSQL
  syn match   railslogSQL         '\u.*$' contained
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

function! s:SetBasePath()
  let rp = s:escapepath(b:rails_root)
  let t = RailsFileType()
  let oldpath = s:sub(&l:path,'^\.,','')
  let &l:path = '.,'.rp.",".rp."/app/controllers,".rp."/app,".rp."/app/models,".rp."/app/helpers,".rp."/components,".rp."/config,".rp."/lib,".rp."/vendor/plugins/*/lib,".rp."/vendor,".rp."/test/unit,".rp."/test/functional,".rp."/test/integration,".rp."/app/apis,"."/test,"
  if s:controller() != ''
    if RailsFilePath() =~ '\<components/'
      let &l:path = &l:path . rp . '/components/' . s:controller() . ','
    else
      let &l:path = &l:path . rp . '/app/views/' . s:controller() . ',' . rp . '/app/views,' . rp . '/public,'
    endif
  endif
  let &l:path = &l:path . oldpath
endfunction

function! s:InitRuby()
  if has("ruby") && ! exists("s:ruby_initialized")
    let s:ruby_initialized = 1
    " Is there a drawback to doing this?
    "        ruby require "rubygems" rescue nil
    "        ruby require "active_support" rescue nil
  endif
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
    let res = s:sub(system("ri ".s:rquote(str)),'\n$','')
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
    return RailsIncludefind(v:fname)
  else
    return RailsIncludefind(v:fname,1)
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
  let cfile = expand("<cfile>")
  let res = RailsIncludefind(cfile,1)
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

function! RailsIncludefind(str,...)
  if a:str == "ApplicationController"
    return "controllers/application.rb"
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
  let word = s:sub(word,'eople$','erson')
  let word = s:sub(word,'[aeio]\@<!ies$','ys')
  let word = s:sub(word,'xe[ns]$','xs')
  let word = s:sub(word,'ves$','fs')
  let word = s:sub(word,'s\@<!s$','')
  return word
endfunction

function! s:Alternate(bang,cmd)
  let cmd = a:cmd.(a:bang?"!":"")
  let f = RailsFilePath()
  let t = RailsFileType()
  if f =~ '\<config/database.yml$' || f =~ '\<config/environments/' || f == 'README'
    exe cmd." environment.rb"
  elseif f =~ '\<config/environment\.rb$' || f =~ '\<db/schema\.rb$'
    exe cmd." database.yml"
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
      exe cmd." ".s:escapepath(helper)
    elseif filereadable(b:rails_root."/".controller)
      let jumpto = expand("%:t:r")
      exe cmd." ".s:escapepath(controller)
      exe "silent! djump ".jumpto
    elseif filereadable(b:rails_root."/".model)
      exe cmd." ".s:escapepath(model)
    else
      exe cmd." ".s:escapepath(helper)
    endif
  elseif t =~ '^controller-api\>'
    let api = s:sub(s:sub(f,'/controllers/','/apis/'),'_controller\.rb$','_api.rb')
    exe cmd." ".s:escapepath(api)
  elseif t =~ '^helper\>'
    let controller = s:sub(s:sub(f,'/helpers/','/controllers/'),'_helper\.rb$','_controller.rb')
    exe cmd." ".s:escapepath(controller)
  elseif t =~ '\<fixtures\>'
    let file = s:singularize(expand("%:t:r")).'_test'
    exe cmd." ".s:escapepath(file)
  else
    let file = fnamemodify(f,":t:r")
    if file =~ '_test$'
      exe cmd." ".s:escapepath(s:sub(file,'_test$',''))
    else
      exe cmd." ".s:escapepath(file).'_test'
    endif
  endif
endfunction

function! s:MagicM(bang,cmd)
  let cmd = a:cmd.(a:bang ? '!' : '')
  let t = RailsFileType()
  if RailsFilePath() == 'README'
    find config/database.yml
  elseif t =~ '^test\>'
    call s:warn('In the future, use :Rake instead')
    Rake
  elseif t =~ '^view\>'
    exe cmd." ".s:sub(s:sub(RailsFilePath(),'/views/','/controllers/'),'/\(\k\+\)\..*$','_controller|silent! djump \1')
  elseif t =~ '^controller-api\>'
    exe cmd." ".s:sub(s:sub(RailsFilePath(),'/controllers/','/apis/'),'_controller\.rb$','_api.rb')
  elseif t =~ '^controller\>'
    exe cmd." ".s:sub(s:sub(RailsFilePath(),'/controllers/','/views/'),'_controller\.rb$','/'.s:lastmethod())
  elseif t =~ '^model-ar\>'
    call s:Migration(0,'create_'.s:sub(expand('%:t:r'),'y$','ie$').'s')
  elseif t =~ '^api\>'
    exe cmd." ".s:sub(s:sub(RailsFilePath(),'/apis/','/controllers/'),'_api\.rb$','_controller.rb')
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
    let out = (b:rails_root).dir."/_".fname
  elseif dir == ""
    let out = (curdir)."/_".fname
  elseif isdirectory(curdir."/".dir)
    let out = (curdir)."/".dir."/_".fname
  else
    let out = (b:rails_root)."/app/views/".dir."/_".fname
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
  exe "silent file ".s:escapepath(fnamemodify(out,':~:.'))
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

function s:leadermap(key,mapping)
  exe "map <buffer> ".g:rails_leader.a:key." ".a:mapping
endfunction

function! s:BufMappings()
  map <buffer> <silent> <Plug>RailsAlternate :Ralternate<CR>
  map <buffer> <silent> <Plug>RailsFind      :Rfind<CR>
  map <buffer> <silent> <Plug>RailsSplitFind :Rsplitfind<CR>
  map <buffer> <silent> <Plug>RailsVSplitFind :Rvsplitfind<CR>
  map <buffer> <silent> <Plug>RailsTabFind   :Rtabfind<CR>
  map <buffer> <silent> <Plug>RailsMagicM    :call <SID>MagicM(0,"find")<CR>
  if g:rails_mappings
    if !hasmapto("<Plug>RailsFind")
      map <buffer> gf              <Plug>RailsFind
    endif
    if !hasmapto("<Plug>RailsSplitFind")
      map <buffer> <C-W>f          <Plug>RailsSplitFind
    endif
    if !hasmapto("<Plug>RailsTabFind")
      map <buffer> <C-W>gf         <Plug>RailsTabFind
    endif
    map <buffer> <LocalLeader>rf <Plug>RailsFind
    map <buffer> <LocalLeader>ra <Plug>RailsAlternate
    map <buffer> <LocalLeader>rm <Plug>RailsMagicM
    call s:leadermap('f','<Plug>RailsFind')
    call s:leadermap('a','<Plug>RailsAlternate')
    call s:leadermap('m','<Plug>RailsMagicM')
    " Deprecated
    call s:leadermap('v',':echoerr "Use <Lt>LocalLeader>rm instead!"<CR>')
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

call s:InitPlugin()

let &cpo = cpo_save

" vim:set sw=2 sts=2:
