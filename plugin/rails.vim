" rails.vim - Detect a rails application
" Author:       Tim Pope <vimNOSPAM@tpope.info>
" Last Change:  2006 May 29
" $Id$

" See doc/rails.txt for details.

" ========

" Exit quickly when:
" - this plugin was already loaded (or disabled)
" - when 'compatible' is set
if exists("g:loaded_rails") && g:loaded_rails || &cp
  finish
endif
let g:loaded_rails = 1

let cpo_save = &cpo
set cpo&vim

function s:gsub(str,pat,rep)
  return substitute(a:str,'\C'.a:pat,a:rep,'g')
endfunction

function s:RubyEval(ruby,...)
  if a:0 > 0
    let def = a:1
  else
    let def = ""
  endif
  if !executable("ruby")
    return def
  endif
  let results = system('ruby -e '.s:qq().'require %{rubygems} rescue nil; require %{active_support} rescue nil; '.a:ruby.s:qq())
  if results =~ '-e:\d'
    return def
  else
    return results
  endif
endfunction

function! s:InitPlugin()
  if has("autocmd")
    augroup <SID>railsDetect
      autocmd!
      autocmd BufNewFile,BufRead * call s:Detect(expand("<afile>:p"))
      autocmd BufEnter * call s:SetGlobals()
      autocmd BufLeave * call s:ClearGlobals()
    augroup END
  endif
  if exists("g:rails_statusline") && g:rails_statusline
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

function! RailsFilePath()
  if !exists("b:rails_app_path")
    return ""
  elseif exists("b:rails_file_path")
    return b:rails_file_path
  endif
  let f = s:gsub(expand("%:p"),'\\ \@!','/')
  if s:gsub(b:rails_app_path,'\\ \@!','/') == strpart(f,0,strlen(b:rails_app_path))
    return strpart(f,strlen(b:rails_app_path)+1)
  else
    return f
  endif
endfunction

function! RailsFileType()
  if !exists("b:rails_app_path")
    return ""
  elseif exists("b:rails_file_type")
    return b:rails_file_type
  endif
  let f = RailsFilePath()
  let e = fnamemodify(RailsFilePath(),':e')
  let r = ""
  let top = getline(1).getline(2).getline(3)
  if f == ""
    let r = f
  elseif f =~ '_controller\.rb$'
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
  elseif f =~ '\<app/models'
    if top =~ '<\s*ActiveRecord::Base\>'
      let r = "model-ar"
    elseif top =~ '<\s*ActionMailer::Base\>'
      let r = "model-am"
    else
      let r = "model"
    endif
  elseif f =~ '\<app/views/layouts\>'
    let r = "view-layout-" . e
  elseif f =~ '\<app/views/.*/_\k\+\.\k\+$'
    let r = "view-partial-" . e
  elseif f =~ '\<app/views\>'
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
  elseif f =~ '\<db/migrations\>'
    let r = "migration"
  elseif e == "css" || e == "js" || e == "html"
    let r = e
  endif
  return r
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
  if exists("b:rails_app_path")
    if !exists("g:rails_isfname") || g:rails_isfname
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
  call s:Syntax()
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
    setlocal includeexpr=RailsIncludeexpr()
  else
    " Does this cause problems in any filetypes?
    setlocal includeexpr=RailsIncludeexpr()
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
  set endofline
  silent doautocmd User Rails*
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

function! s:Syntax()
  if exists("g:rails_syntax") && g:rails_syntax && (exists("g:syntax_on") || exists("g:syntax_manual"))
    let t = RailsFileType()
    if !exists("s:rails_view_helpers")
      let s:rails_view_helpers = s:RubyEval('require %{action_view}; puts ActionView::Helpers.constants.select {|c| c =~ /Helper$/}.collect {|c|ActionView::Helpers.const_get c}.collect {|c| c.public_instance_methods(false)}.flatten.sort.uniq.reject {|m| m =~ /[=?]$/}.join(%{ })',"form_tag end_form_tag")
    endif
"    let g:rails_view_helpers = s:rails_view_helpers
    let rails_view_helpers = '+\.\@<!\<\('.s:gsub(s:rails_view_helpers,'\s\+','\\|').'\)\>+'
    if &syntax == 'ruby'
      if t =~ '^model$' || t =~ '^model-ar\>'
        syn keyword railsRubyModelActsMethod acts_as_list acts_as_nested_set acts_as_tree
        syn keyword railsRubyModelAssociationMethod belongs_to has_one has_many has_and_belongs_to_many
        syn match railsRubyModelCallbackMethod '\<\(before\|after\)_\(create\|destroy\|save\|update\|validation\|validation_on_create\|validation_on_update\)\>'
        syn keyword railsRubyModelClassMethod attr_accessible attr_protected establish_connection set_inheritance_column set_locking_column set_primary_key set_sequence_name set_table_name
        syn keyword railsRubyModelValidationMethod validate validate_on_create validate_on_update validates_acceptance_of validates_associated validates_confirmation_of validates_each validates_exclusion_of validates_format_of validates_inclusion_of validates_length_of validates_numericality_of validates_presence_of validates_size_of validates_uniqueness_of
        syn match railsRubyModelCallbackMethod '\<after_\(find\|initialize\)\>'
        hi def link railsRubyModelActsMethod        railsRubyModelMethod
        hi def link railsRubyModelAssociationMethod railsRubyModelMethod
        hi def link railsRubyModelCallbackMethod    railsRubyModelMethod
        hi def link railsRubyModelClassMethod       railsRubyModelMethod
        hi def link railsRubyModelValidationMethod  railsRubyModelMethod
        hi def link railsRubyModelMethod            railsRubyMethod
      endif
      if t =~ '^controller\>' || t =~ '^view\>' || t=~ '^helper\>'
        syn match railsRubyMethod '\<\%(params\|request\|response\|session\|headers\|template\|cookies\|flash\)\>'
        syn match railsRubyError '@\%(params\|request\|response\|session\|headers\|template\|cookies\|flash\)\>'
        syn keyword railsRubyRenderMethod render render_component
        hi def link railsRubyRenderMethod           railsRubyMethod
      endif
      if t =~ '^helper\>' || t=~ '^view\>'
        exe "syn match railsRubyHelperMethod ".rails_view_helpers
        hi def link railsRubyHelperMethod           railsRubyMethod
      elseif t =~ '^controller'
        syn keyword railsRubyRenderMethod render_to_string render_component_as_string
      endif
      if t=~ '^test\>'
        if !exists("s:rails_test_asserts")
          " TODO: ActionController::Assertions
          let s:rails_test_asserts = s:RubyEval('require %{test/unit/testcase}; puts Test::Unit::TestCase.instance_methods.grep(/^assert/).sort.uniq.join(%{ })',"assert_equal")
        endif
        "let g:rails_test_asserts = s:rails_test_asserts
        let rails_test_asserts = '+\.\@<!\<\('.s:gsub(s:rails_test_asserts,'\s\+','\\|').'\)\>+'
        exe "syn match railsRubyTestMethod ".rails_test_asserts
        hi def link railsRubyTestMethod             railsRubyMethod
      endif
      hi def link railsRubyError rubyError
      hi def link railsRubyMethod railsMethod
      hi def link railsMethod rubyFunction
    elseif &syntax == "eruby" && t =~ '^view\>'
      exe "syn match railsErubyHelperMethod ".rails_view_helpers." containedin=@erubyRegions"
        syn match railsErubyMethod '\<\%(params\|request\|response\|session\|headers\|template\|cookies\|flash\)\>' containedin=@erubyRegions
        syn match railsErubyMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' containedin=@erubyRegions
      syn match railsRubyError '@\%(params\|request\|response\|session\|headers\|template\|cookies\|flash\)\>' containedin=@erubyRegions
      hi def link railsRubyError                    rubyError
      hi def link railsErubyHelperMethod            railsErubyMethod
      hi def link railsErubyMethod                  railsMethod
      hi def link railsMethod                       rubyFunction
    elseif &syntax == "yaml"
      " Modeled after syntax/eruby.vim
      unlet b:current_syntax
      let g:main_syntax = 'eruby'
      syn include @rubyTop syntax/ruby.vim
      unlet g:main_syntax
      syn cluster railsYamlRegions contains=railsYamlOneLiner,railsYamlBlock,railsYamlExpression,railsYamlComment
      syn region  railsYamlOneLiner   matchgroup=railsYamlDelimiter start="^%%\@!" end="$"  contains=@railsRubyTop	       containedin=ALLBUT,@railsYamlRegions keepend oneline
      syn region  railsYamlBlock	    matchgroup=railsYamlDelimiter start="<%%\@!" end="%>" contains=@rubyTop	       containedin=ALLBUT,@railsYamlRegions
      syn region  railsYamlExpression matchgroup=railsYamlDelimiter start="<%="    end="%>" contains=@rubyTop	       containedin=ALLBUT,@railsYamlRegions
      syn region  railsYamlComment    matchgroup=railsYamlDelimiter start="<%#"    end="%>" contains=rubyTodo,@Spell containedin=ALLBUT,@railsYamlRegions keepend
        syn match railsYamlMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' containedin=@erubyRegions
      hi def link railsYamlDelimiter              Delimiter
      hi def link railsYamlMethod                 railsMethod
      hi def link railsMethod                     rubyFunction
      hi def link railsYamlComment                Comment
      let b:current_syntax = "yaml"
    endif
  endif
endfunction

function! s:EscapePath(p)
  return s:gsub(a:p,' ','\\ ')
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

function! RailsIncludeexpr()
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
  let str = s:gsub(str,"[\"']",'')
  if line =~ '\<\(require\|load\)\s*(\s*$'
    return str
  endif
  let str = s:gsub(str,'::','/')
  let str = s:gsub(str,'\(\u\+\)\(\u\l\)','\1_\2')
  let str = s:gsub(str,'\(\l\|\d\)\(\u\)','\1_\2')
  let str = s:gsub(str,'-','_')
  let str = tolower(str)
  let fpat = '\(\s*\%("\f*"\|:\f*\|'."'\\f*'".'\)\s*,\s*\)*'
  if a:str =~ '\u'
    " Classes should always be in .rb files
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
  let f = RailsFilePath()
  let t = RailsFileType()
  if expand("%:t") == "database.yml" || f =~ '\<config/environments/'
    find environment.rb
  elseif expand("%:t") == "environment.rb" || expand("%:t") == "schema.rb"
    find database.yml
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
    if filereadable(b:rails_app_path."/".helper)
      " Would it be better to skip the helper and go straight to the
      " controller?
      exe "find ".s:EscapePath(helper)
    elseif filereadable(b:rails_app_path."/".controller)
      exe "find ".s:EscapePath(controller)
    elseif filereadable(b:rails_app_path."/".model)
      exe "find ".s:EscapePath(model)
    else
      exe "find ".s:EscapePath(controller)
    endif
  elseif t =~ '^helper\>'
    let controller = substitute(substitute(f,'/helpers/','/controllers/',''),'_helper\.rb$','_controller.rb','')
    exe "find ".s:EscapePath(controller)
  elseif t =~ '\<fixtures\>'
    let file = s:RailsSingularize(expand("%:t:r")).'_test'
    exe "find ".s:EscapePath(file)
  else
    let file = fnamemodify(f,":t:r")
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
    let &statusline=substitute(&statusline,'\C%Y','%Y%{RailsSTATUSLINE()}','')
    let &statusline=substitute(&statusline,'\C%y','%y%{RailsStatusline()}','')
  endif
endfunction

function! RailsStatusline()
  if exists("b:rails_app_path")
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
  if exists("b:rails_app_path")
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

call s:InitPlugin()

let &cpo = cpo_save

" vim:set sw=2 sts=2:
