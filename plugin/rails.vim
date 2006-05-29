" rails.vim - Detect a rails application
" Author:       Tim Pope <vimNOSPAM@tpope.info>
" Last Change:  2006 May 23
" $Id$

" See doc/rails.txt for details.

" ========

" Exit quickly when:
" - this plugin was already loaded (or disabled)
" - when 'compatible' is set
if exists("g:loaded_rails") || &cp
  finish
endif
let g:loaded_rails = 1

let cpo_save = &cpo
set cpo&vim

function! s:InitPlugin()
  if has("autocmd")
    augroup <SID>railsDetect
      autocmd!
      autocmd BufNewFile,BufRead * call s:Detect(expand("<afile>:p"))
      autocmd BufEnter * call s:SetGlobals()
      autocmd BufLeave * call s:ClearGlobals()
    augroup END
  endif
  if exists("g:rails_statusline")
    call s:InitStatusline()
  endif
endfunction

function! RailsAppPath()
  if exists("b:rails_app_path")
    return b:rails_app_path
  else
    return ""
  endif
endfunction

function! s:qq()
  " Quote character
  if &shellxquote == "'"
    return '"'
  else
    return "'"
  endif
endfunction

function! s:Detect(filename)
  let fn = fnamemodify(a:filename,":p")
  if isdirectory(fn)
    let fn = fnamemodify(fn,":s?[\/]$??")
  else
    let fn = fnamemodify(fn,':s?\(.*\)[\/][^\/]*$?\1?')
  endif
  let ofn = ""
  while fn != ofn
    if filereadable(fn . "/config/environment.rb")
      return s:InitBuffer(fn)
    endif
    let ofn = fn
    let fn = fnamemodify(ofn,':s?\(.*\)[\/]\(app\|components\|config\|db\|doc\|lib\|log\|public\|script\|test\|tmp\|vendor\)\($\|[\/].*$\)?\1?')
  endwhile
  return 0
endfunction

function! s:SetGlobals()
  if exists("b:rails_app_path") && !exists("g:rails_no_isfname")
    let b:rails_restore_isfname=&isfname
    set isfname=@,48-57,/,-,_,\",',:
  endif
endfunction

function! s:ClearGlobals()
  if exists("b:rails_restore_isfname")
    let &isfname=b:rails_restore_isfname
    unlet b:rails_restore_isfname
  endif
endfunction

function! s:InitBuffer(path)
  call s:InitRuby()
  let b:rails_app_path = a:path
  let rp = s:EscapePath(b:rails_app_path)
  if &ft == "mason"
    setlocal filetype=eruby
  endif
  if &ft == "" && ( expand("%:e") == "rjs" || expand("%:e") == "rxml" )
    setlocal filetype=ruby
  endif
  call s:Commands()
  silent! compiler rubyunit
  let &l:makeprg='rake -f '.rp.'/Rakefile'
  call s:SetRubyBasePath()
  if &ft == "ruby" || &ft == "eruby" || &ft == "rjs" || &ft == "rxml"
    " This is a strong convention in Rails, so we'll break the usual rule
    " of considering shiftwidth to be a personal preference
    setlocal sw=2 sts=2 et
    " It would be nice if we could do this without pulling in half of Rails
    " set include=\\<\\zs\\u\\f*\\l\\f*\\ze\\>\\\|^\\s*\\(require\\\|load\\)\\s\\+['\"]\\zs\\f\\+\\ze
    set include=\\<\\zsAct\\f*::Base\\ze\\>\\\|^\\s*\\(require\\\|load\\)\\s\\+['\"]\\zs\\f\\+\\ze
    setlocal includeexpr=RailsFilename()
  else
    " Does this cause problems in any filetypes?
    setlocal includeexpr=RailsFilename()
    setlocal suffixesadd=.rb,.rhtml,.rxml,.rjs,.css,.js,.yml,.csv,.rake,.sql,.html
  endif
  if &filetype == "ruby"
    setlocal suffixesadd=.rb,.rhtml,.rxml,.rjs,.yml,.csv,.rake,s.rb
    setlocal define=^\\s*def\\s\\+\\(self\\.\\)\\=
    let views = substitute(expand("%:p"),'[\/]app[\/]controllers[\/]\(.\{-\}\)_controller.rb','/app/views/\1','')
    if views != expand("%:p")
      let &l:path = &l:path.",".s:EscapePath(views)
    endif
  elseif &filetype == "eruby"
    set include=\\<\\zsAct\\f*::Base\\ze\\>\\\|^\\s*\\(require\\\|load\\)\\s\\+['\"]\\zs\\f\\+\\ze\\\|\\zs<%=\\ze
    setlocal suffixesadd=.rhtml,.rxml,.rjs,.rb,.css,.js
    let &l:path = rp."/app/views,".&l:path.",".rp."/public"
  endif
  " Since so many generated files are malformed...
  set eol
  silent doautocmd User rails
  if filereadable(b:rails_app_path."/config/rails.vim")
    sandbox exe "source ".rp."/config/rails.vim"
  endif
  return b:rails_app_path
endfunction

function s:Commands()
  let rp = s:EscapePath(b:rails_app_path)
  silent exe 'command! -buffer -nargs=+ Script :!ruby '.s:EscapePath(b:rails_app_path.'/script/').'<args>'
  if b:rails_app_path =~ ' '
    " irb chokes if there is a space in $0
    silent exe 'command! -buffer -nargs=* Console :!ruby '.substitute(s:qq().fnamemodify(b:rails_app_path.'/script/console',":~:."),'"\~/','\~/"','').s:qq().' <args>'
  else
    command! -buffer -nargs=* Console :Script console <args>
  endif
  command! -buffer -nargs=1 Controller :find <args>_controller
  silent exe "command! -buffer -nargs=? Cd :cd ".rp."/<args>"
  silent exe "command! -buffer -nargs=? Lcd :lcd ".rp."/<args>"
  let ext = expand("%:e")
  command! -buffer -nargs=0 Alternate :call s:FindAlternate()
  map <buffer> <silent> <Plug>RailsAlternate :Alternate<CR>
  if ext == "rhtml" || ext == "rxml" || ext == "rjs"
    command! -buffer -nargs=? -range Partial :<line1>,<line2>call s:MakePartial(<bang>0,<f-args>)
  endif
endfunction

function! s:EscapePath(p)
  return substitute(a:p,' ','\\ ','g')
endfunction

function! s:SetRubyBasePath()
  let rp = s:EscapePath(b:rails_app_path)
  let &l:path = '.,'.rp.",".rp."/app/controllers,".rp."/app,".rp."/app/models,".rp."/app/helpers,".rp."/components,".rp."/config,".rp."/lib,".rp."/vendor/plugins/*/lib,".rp."/vendor,".rp."/test/unit,".rp."/test/functional,".rp."/test/integration,".rp."/test,".substitute(&l:path,'^\.,','','')
endfunction

function! s:InitRuby()
  if has("ruby") && ! exists("s:ruby_initialized")
    let s:ruby_initialized = 1
    " Is there a drawback to doing this?
    "        ruby require "rubygems" rescue nil
    "        ruby require "active_support" rescue nil
  endif
endfunction

function! RailsFilename()
  " Is this foolproof?
  if mode() =~ '[iR]' || expand("<cfile>") != v:fname
    return s:RailsUnderscore(v:fname)
  else
    return s:RailsUnderscore(v:fname,line("."),col("."))
  endif
endfunction

function! s:RailsUnderscore(str,...)
  if a:str == "ApplicationController"
    return "controllers/application.rb"
  elseif a:str == "<%="
    " Probably a silly idea
    return "action_view.rb"
  endif
  let g:mymode = mode()
  let str = a:str
  if a:0 == 2
    " Get the text before the filename under the cursor.
    " We'll cheat and peak at this in a bit
    let line = getline(a:1)
    let line = substitute(line,'^\(.\{'.a:2.'\}\).*','\1','')
    let line = substitute(line,'\([:"'."'".']\|%[qQ]\=[[({<]\)\=\f*$','','')
  else
    let line = ""
  endif
  let str = substitute(str,'^\s*','','')
  let str = substitute(str,'\s*$','','')
  let str = substitute(str,'^[:@]','','')
  "    let str = substitute(str,"\\([\"']\\)\\(.*\\)\\1",'\2','')
  let str = substitute(str,"[\"']",'','g')
  if line =~ '\<\(require\|load\)\s*(\s*$'
    return str
  endif
  let str = substitute(str,'::','/','g')
  let str = substitute(str,'\(\u\+\)\(\u\l\)','\1_\2','g')
  let str = substitute(str,'\(\l\|\d\)\(\u\)','\1_\2','g')
  let str = substitute(str,'-','_','g')
  let str = substitute(str,'.*','\L&','')
  let fpat = '\(\s*\%("\f*"\|:\f*\|'."'\\f*'".'\)\s*,\s*\)*'
  if a:str =~ '\u'
    " Classes should always be in .rb's
    let str = str . '.rb'
  elseif line =~ '\(:partial\|"partial"\|'."'partial'".'\)\s*=>\s*'
    let str = substitute(str,'\([^/]\+\)$','_\1','')
    let str = substitute(str,'^/','views/','')
  elseif line =~ '\<layout\s*(\=\s*' || line =~ '\(:layout\|"layout"\|'."'layout'".'\)\s*=>\s*'
    let str = substitute(str,'^/\=','views/layouts/','')
  elseif line =~ '\(:controller\|"controller"\|'."'controller'".'\)\s*=>\s*'
    let str = 'controllers/'.str.'_controller.rb'
  elseif line =~ '\<helper\s*(\=\s*'
    let str = 'helpers/'.str.'_helper.rb'
  elseif line =~ '\<fixtures\s*(\='.fpat
    let str = substitute(str,'^/\@!','test/fixtures/','')
  elseif line =~ '\<stylesheet_\(link_tag\|path\)\s*(\='.fpat
    let str = substitute(str,'^/\@!','/stylesheets/','')
    let str = 'public'.substitute(str,'^[^.]*$','&.css','')
  elseif line =~ '\<javascript_\(include_tag\|path\)\s*(\='.fpat
    if str == "defaults"
      let str = "application"
    endif
    let str = substitute(str,'^/\@!','/javascripts/','')
    let str = 'public'.substitute(str,'^[^.]*$','&.js','')
  elseif line =~ '\<\(has_one\|belongs_to\)\s*(\=\s*'
    let str = 'models/'.str.'.rb'
  elseif line =~ '\<has_\(and_belongs_to_\)\=many\s*(\=\s*'
    let str = 'models/'.s:RailsSingularize(str).'.rb'
  elseif line =~ '\<def\s\+' && expand("%:t") =~ '_controller\.rb'
    let str = substitute(expand("%:p"),'.*[\/]app[\/]controllers[\/]\(.\{-\}\)_controller.rb','views/\1','').'/'.str
  else
    " If we made it this far, we'll risk making it singular.
    let str = s:RailsSingularize(str)
    let str = substitute(str,'_id$','','')
  endif
  if str =~ '^/' && !filereadable(str)
    let str = substitute(str,'^/','','')
  endif
  return str
endfunction

function! s:RailsSingularize(word)
  " Probably not worth it to be as comprehensive as Rails but we can
  " still hit the common cases.
  let word = a:word
  let word = substitute(word,'eople$','erson','')
  let word = substitute(word,'[aeio]\@<!ies$','ys','')
  let word = substitute(word,'xe[ns]$','xs','')
  let word = substitute(word,'ves$','fs','')
  let word = substitute(word,'s$','','')
  return word
endfunction

function s:MakePartial(bang,...) range abort
  if a:0 == 0 || a:0 > 1
    echoerr "Incorrect number of arguments"
    return
  endif
  if a:1 =~ '[^a-z0-9_/]'
    echoerr "Invalid partial name"
    return
  endif
  let file = a:1
  let range = a:firstline.",".a:lastline
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
  if dir =~ '^/'
    let out = s:EscapePath(b:rails_app_path).dir."/_".fname
  elseif dir == ""
    let out = s:EscapePath(curdir)."/_".fname
  elseif isdirectory(curdir."/".dir)
    let out = s:EscapePath(curdir)."/".dir."/_".fname
  else
    let out = s:EscapePath(b:rails_app_path)."/app/views/".dir."/_".fname
  endif
  " No tabs, they'll just complicate things
  let spaces = matchstr(getline(a:firstline),"^ *")
  if spaces != ""
    silent! exe range.'sub/'.spaces.'//'
  endif
  silent! exe range.'sub?\w\@<!'.var.'\>?'.name.'?g'
  silent exe range."write ".out
  let renderstr = "render :partial => '".fnamemodify(file,":r")."'"
  if "@".name != var
    let renderstr = renderstr.", :object => ".var
  endif
  if expand("%:e") == "rhtml"
    let renderstr = "<%= ".renderstr." %>"
  endif
  silent exe "norm :".range."change\<CR>".spaces.renderstr."\<CR>.\<CR>"
  if renderstr =~ '<%'
    norm ^6w
  else
    norm ^5w
  endif
endfunction

function s:FindAlternate()
  if expand("%:t") == "database.yml"
    find environment.rb
  elseif expand("%:t") == "environment.rb" || expand("%:t") == "schema.rb"
    find database.yml
  elseif expand("%:p") =~ '[\/]app[\/]views[\/]'
    " Go to the helper, controller, or model
    let helper = s:EscapePath(expand("%:p:h:s?.*[\/]app[\/]views[\/]?app/helpers/?")."_helper.rb")
    let controller = s:EscapePath(expand("%:p:h:s?.*[\/]app[\/]views[\/]?app/controllers/?")."_controller.rb")
    let model = s:EscapePath(expand("%:p:h:s?.*[\/]app[\/]views[\/]?app/models/?").".rb")
    if filereadable(b:rails_app_path."/".helper)
      " Would it be better to skip the helper and go straight to the
      " controller?
      exe "find ".helper
    elseif filereadable(b:rails_app_path."/".controller)
      exe "find ".controller
    elseif filereadable(b:rails_app_path."/".model)
      exe "find ".model
    else
      exe "find ".controller
    endif
  elseif expand("%:p") =~ '/app/helpers/.*_helper\.rb$'
    let controller = s:EscapePath(expand("%:p:s?.*[\/]app[\/]helpers[\/]?app/controllers/?:s?_helper.rb$?_controller.rb?"))
    exe "find ".controller
  elseif expand("%:e") == "csv" || expand("%:e") == "yml"
    let file = s:RailsSingularize(expand("%:t:r")).'_test'
    exe "find ".s:EscapePath(file)
  else
    let file = expand("%:t:r")
    if file =~ '_test$'
      exe "find ".s:EscapePath(substitute(file,'_test$','',''))
    else
      exe "find ".s:EscapePath(file).'_test'
    endif
  endif
endfunction

" Statusline {{{1
function! s:InitStatusline()
  if &statusline !~ 'Rails'
    let &statusline=substitute(&statusline,'%y','%y%{RailsStatusline()}','')
    let &statusline=substitute(&statusline,'%Y','%Y%{RailsSTATUSLINE()}','')
  endif
endfunction

function! RailsStatusline()
  if exists("b:rails_app_path")
    return "[Rails]"
  else
    return ""
  endif
endfunction

function! RailsSTATUSLINE()
  if exists("b:rails_app_path")
    return ",RAILS"
  else
    return ""
  endif
endfunction
" }}}1

call s:InitPlugin()

let &cpo = cpo_save

" vim:set sw=2 sts=2:
