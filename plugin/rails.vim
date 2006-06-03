" rails.vim - Detect a rails application
" Author:       Tim Pope <vimNOSPAM@tpope.info>
" Last Change:  2006 Jun 01
" GetLatestVimScripts: 1567 1 :AutoInstall: rails.vim
" URL:          http://svn.tpope.net/rails/vim/railsvim
" $Id$

" See doc/rails.txt for details. Grab it from the URL above if you don't have it
" To access it from Vim, see :help add-local-help (hint: :helptags ~/.vim/doc)
" Afterwards, you should be able to do :help rails

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

function s:sub(str,pat,rep)
  return substitute(a:str,'\C'.a:pat,a:rep,'')
endfunction

function s:gsub(str,pat,rep)
  return substitute(a:str,'\C'.a:pat,a:rep,'g')
endfunction

function s:quote(str)
  " Imperfect but adequate for Ruby arguments
  if a:str =~ '^[A-Za-z0-9_/.-]\+$'
    return a:str
  else
    return "'".s:gsub(s:gsub(a:str,'\','\\'),"'","'\\\\''")."'"
  endif
endfunction

function! s:EscapePath(p)
  return s:gsub(a:p,' ','\\ ')
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

function! s:SetOptDefault(opt,val)
  if !exists("g:".a:opt)
    exe "let g:".a:opt." = ".a:val
  endif
endfunction

function! s:InitConfig()
  call s:SetOptDefault("rails_level",2)
  let l = g:rails_level
  call s:SetOptDefault("rails_statusline",l>2)
  call s:SetOptDefault("rails_syntax",l>1)
  call s:SetOptDefault("rails_isfname",l>1)
  call s:SetOptDefault("rails_mappings",l>2)
  call s:SetOptDefault("rails_abbreviations",l>5)
  call s:SetOptDefault("rails_subversion",l>3)
  if l > 3
    call s:SetOptDefault("ruby_no_identifiers",1)
    call s:SetOptDefault("rubycomplete_rails",1)
  endif
"  call s:SetOptDefault("",)
endfunction

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
    augroup END
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
  let top = getline(1).getline(2).getline(3).getline(4).getline(5)
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
  elseif f =~ '\<app/models'
    if top =~ '\<ActionMailer::Base\>'
      let r = "model-am"
    elseif top =~ '\<ActionWebService::Strut\>'
      let r = "model-aws"
    elseif top =~ '\<ActiveRecord::Base\>' || top =~ '\<validates_\w\+_of\>'
      let r = "model-ar"
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
  elseif f =~ '\<db/migrate\>'
    let r = "migration"
  elseif f =~ '\<lib/tasks\>' || f=~ '\<Rakefile$'
    let r = "task"
  elseif e == "css" || e == "js" || e == "html"
    let r = e
  endif
  return r
endfunction

function s:UseSubversion()
  if exists("b:rails_use_subversion")
    return b:rails_use_subversion
  else
    let b:rails_use_subversion = g:rails_subversion && 
          \ (RailsAppPath()!="") && isdirectory(RailsAppPath()."/.svn")
    return b:rails_use_subversion
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
  if g:rails_level > 0
    if &ft == "mason"
      setlocal filetype=eruby
    endif
    if &ft == "" && ( expand("%:e") == "rjs" || expand("%:e") == "rxml" )
      setlocal filetype=ruby
    endif
    call s:Syntax()
    call s:Commands()
    call s:Mappings()
    call s:Abbreviations()
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
  endif
  let t = RailsFileType()
  if t != ""
    let t = "-".t
  endif
  exe "silent doautocmd User Rails".t."-"
  if filereadable(b:rails_app_path."/config/rails.vim")
    sandbox exe "source ".rp."/config/rails.vim"
  endif
  return b:rails_app_path
endfunction

" Commands {{{1

function s:Commands()
  let rp = s:EscapePath(b:rails_app_path)
"  silent exe 'command! -buffer -complete=custom,s:ScriptComplete -nargs=+ Script :!ruby '.s:EscapePath(b:rails_app_path.'/script/').'<args>'
  command! -buffer -complete=custom,s:ScriptComplete -nargs=+ Script :call s:Script(<bang>0,<f-args>)
  command! -buffer -complete=custom,s:ConsoleComplete -nargs=* Console :Script console <args>
  command! -buffer -nargs=1 Runner :call s:Script(<bang>0,"runner",<f-args>)
  "command! -buffer -nargs=1 Controller :find <args>_controller
  silent exe "command! -buffer -nargs=? Cd :cd ".rp."/<args>"
  silent exe "command! -buffer -nargs=? Lcd :lcd ".rp."/<args>"
  let ext = expand("%:e")
  command! -buffer -nargs=0 Alternate :call s:FindAlternate()
  if ext == "rhtml" || ext == "rxml" || ext == "rjs"
    command! -buffer -nargs=? -range Partial :<line1>,<line2>call s:MakePartial(<bang>0,<f-args>)
  endif
endfunction

function s:Script(bang,cmd,...)
  let str = ""
  let c = 1
  while c <= a:0
    let str = str . " " . s:quote(a:{c})
    let c = c + 1
  endwhile
  exe "!ruby -C ".s:quote(RailsAppPath())." ".s:quote("script/".a:cmd).str
endfunction

function s:ScriptComplete(ArgLead,CmdLine,P)
  "  return s:gsub(glob(RailsAppPath()."/script/**"),'\%(.\%(\n\)\@<!\)*[\/]script[\/]','')
  let cmd = s:sub(a:CmdLine,'^\u\w*\s\+','')
  let g:A = a:ArgLead
  let g:L = cmd
  let g:P = a:P
  if cmd !~ '^[ A-Za-z0-9_-]*$'
    " You're on your own, bud
    return ""
  elseif cmd =~ '^\w*$'
    return "about\nbreakpointer\nconsole\ndestroy\ngenerate\nperformance/benchmarker\nperformance/profiler\nplugin\nproccess/reaper\nprocess/spawner\nrunner\nserver"
  elseif cmd =~ '^\%(generate\|destroy\)\s\+'.a:ArgLead."$"
    return "controller\nintegration_test\nmailer\nmigration\nmodel\nplugin\nscaffold\nsession_migration\nweb_service"
  elseif cmd =~ '^\%(console\)\s\+\(--\=\w\+\s\+\)\='.a:ArgLead."$"
    return "development\ntest\nproduction\n-s\n--sandbox"
  elseif cmd =~ '^\%(plugin\)\s\+'.a:ArgLead."$"
    return "discover\nlist\ninstall\nupdate\nremove\nsource\nunsource\nsources"
  endif
  return ""
"  return s:RealMansGlob(RailsAppPath()."/script",a:ArgLead."*")
endfunction

function s:CustomComplete(A,L,P,cmd)
  let L = "Script ".a:cmd." ".s:sub(a:L,'^\h\w*\s\+','')
  let P = a:P - strlen(a:L) + strlen(L)
  return s:ScriptComplete(a:A,L,P)
endfunction

function s:ConsoleComplete(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"console")
endfunction

function s:RealMansGlob(path,glob)
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

function! s:Syntax()
  if (!exists("g:rails_syntax") || g:rails_syntax) && (exists("g:syntax_on") || exists("g:syntax_manual"))
    let t = RailsFileType()
    if !exists("s:rails_view_helpers")
      let s:rails_view_helpers = s:RubyEval('require %{action_view}; puts ActionView::Helpers.constants.grep(/Helper$/).collect {|c|ActionView::Helpers.const_get c}.collect {|c| c.public_instance_methods(false)}.flatten.sort.uniq.reject {|m| m =~ /[=?]$/}.join(%{ })',"h form_tag end_form_tag")
    endif
    "let g:rails_view_helpers = s:rails_view_helpers
    let rails_view_helpers = '+\.\@<!\<\('.s:gsub(s:rails_view_helpers,'\s\+','\\|').'\)\>+'
    if &syntax == 'ruby'
      if t =~ '^api\>'
        syn keyword railsRubyAPIMethod api_method
        hi link railsRubyAPIMethod railsRubyMethod
      endif
      if t =~ '^model$' || t =~ '^model-ar\>'
        syn keyword railsRubyARMethod acts_as_list acts_as_nested_set acts_as_tree composed_of
        syn keyword railsRubyARAssociationMethod belongs_to has_one has_many has_and_belongs_to_many
        syn match railsRubyARCallbackMethod '\<\(before\|after\)_\(create\|destroy\|save\|update\|validation\|validation_on_create\|validation_on_update\)\>'
        syn keyword railsRubyARClassMethod attr_accessible attr_protected establish_connection set_inheritance_column set_locking_column set_primary_key set_sequence_name set_table_name
        syn keyword railsRubyARValidationMethod validate validate_on_create validate_on_update validates_acceptance_of validates_associated validates_confirmation_of validates_each validates_exclusion_of validates_format_of validates_inclusion_of validates_length_of validates_numericality_of validates_presence_of validates_size_of validates_uniqueness_of
"        syn match railsRubyARMethod +\<(acts_as_list\|acts_as_tree\|after_create\|after_destroy\|after_save\|after_update\|after_validation\|after_validation_on_create\|after_validation_on_update\|before_create\|before_destroy\|before_save\|before_update\|before_validation\|before_validation_on_create\|before_validation_on_update\|composed_of\|belongs_to\|has_one\|has_many\|has_and_belongs_to_many\|helper\|helper_method\|validate\|validate_on_create\|validates_numericality_of\|validate_on_update\|validates_acceptance_of\|validates_associated\|validates_confirmation_of\|validates_each\|validates_format_of\|validates_inclusion_of\|validates_length_of\|validates_presence_of\|validates_size_of\|validates_uniqueness_of\|attr_protected\|attr_accessible)\>+
        "syn match railsRubyARCallbackMethod '\<after_\(find\|initialize\)\>'
        hi def link railsRubyARAssociationMethod    railsRubyARMethod
        hi def link railsRubyARCallbackMethod       railsRubyARMethod
        hi def link railsRubyARClassMethod          railsRubyARMethod
        hi def link railsRubyARValidationMethod     railsRubyARMethod
        hi def link railsRubyARMethod               railsRubyMethod
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
      elseif t =~ '^controller\>'
        syn keyword railsRubyControllerHelperMethod helper helper_attr helper_method
        "syn match railsRubyControllerMethod +\<(before_filter\|skip_before_filter\|skip_after_filter\|after_filter\|filter\|layout\|require_dependency\|render\|render_action\|render_text\|render_file\|render_template\|render_nothing\|render_component\|render_without_layout\|url_for\|redirect_to\|redirect_to_path\|redirect_to_url\|helper\|helper_method\|model\|service\|observer\|serialize\|scaffold\|verify)\>+
        syn keyword railsRubyControllerDeprecatedMethod render_action render_text render_file render_template render_nothing render_without_layout
        syn keyword railsRubyRenderMethod render_to_string render_component_as_string redirect_to
        syn match railsRubyFilterMethod '\<\(append_\|prepend_\|\)\(before\|around\|after\)_filter\>'
        syn match railsRubyFilterMethod '\<skip_\(before\|after\)_filter\>'
        syn keyword railsRubyFilterMethod verify
        hi def link railsRubyControllerHelperMethod railsRubyMethod
        hi def link railsRubyControllerDeprecatedMethod railsRubyError
        hi def link railsRubyFilterMethod           railsRubyMethod
      endif
      if t=~ '^test\>'
"        if !exists("s:rails_test_asserts")
"          let s:rails_test_asserts = s:RubyEval('require %{test/unit/testcase}; puts Test::Unit::TestCase.instance_methods.grep(/^assert/).sort.uniq.join(%{ })',"assert_equal")
"        endif
"        let rails_test_asserts = '+\.\@<!\<\('.s:gsub(s:rails_test_asserts,'\s\+','\\|').'\)\>+'
"        exe "syn match railsRubyTestMethod ".rails_test_asserts
        syn match railsRubyTestMethod +\.\@<!\<\(add_assertion\|assert\|assert_block\|assert_equal\|assert_in_delta\|assert_instance_of\|assert_kind_of\|assert_match\|assert_nil\|assert_no_match\|assert_not_equal\|assert_not_nil\|assert_not_same\|assert_nothing_raised\|assert_nothing_thrown\|assert_operator\|assert_raise\|assert_respond_to\|assert_same\|assert_send\|assert_throws\|flunk\)\>+
        syn match railsRubyTestControllerMethod +\.\@<!\<\(assert_response\|assert_redirected_to\|assert_template\|assert_recognizes\|assert_generates\|assert_routing\|assert_tag\|assert_no_tag\|assert_dom_equal\|assert_dom_not_equal\|assert_valid\)\>+
        hi def link railsRubyTestControllerMethod   railsRubyTestMethod
        hi def link railsRubyTestMethod             railsRubyMethod
      endif
      syn keyword railsRubyMethod cattr_accessor mattr_accessor
      syn keyword railsRubyInclude require_dependency require_gem
      hi def link railsRubyError    rubyError
      hi def link railsRubyInclude  rubyInclude
      hi def link railsRubyMethod   railsMethod
      hi def link railsMethod Function
    elseif &syntax == "eruby" && t =~ '^view\>'
      syn cluster railsErubyRegions contains=erubyOneLiner,erubyBlock,erubyExpression
      exe "syn match railsErubyHelperMethod ".rails_view_helpers." contained containedin=@railsErubyRegions"
      syn match railsErubyMethod '\<\%(params\|request\|response\|session\|headers\|template\|cookies\|flash\)\>' contained containedin=@railsErubyRegions
"      syn match railsErubyMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' contained containedin=@railsErubyRegions
        syn keyword railsErubyRenderMethod render render_component contained containedin=@railsErubyRegions
      syn match railsRubyError '@\%(params\|request\|response\|session\|headers\|template\|cookies\|flash\)\>' contained containedin=@railsErubyRegions
      hi def link railsRubyError                    rubyError
      hi def link railsErubyHelperMethod            railsErubyMethod
      hi def link railsErubyRenderMethod            railsErubyMethod
      hi def link railsErubyMethod                  railsMethod
      hi def link railsMethod                       Function
    elseif &syntax == "yaml"
      " Modeled after syntax/eruby.vim
      unlet b:current_syntax
      let g:main_syntax = 'eruby'
      syn include @rubyTop syntax/ruby.vim
      unlet g:main_syntax
      syn cluster erubyRegions contains=railsYamlOneLiner,railsYamlBlock,railsYamlExpression,railsYamlComment
      syn cluster railsErubyRegions contains=railsYamlOneLiner,railsYamlBlock,railsYamlExpression
      syn region  railsYamlOneLiner   matchgroup=railsYamlDelimiter start="^%%\@!" end="$"  contains=@railsRubyTop	       containedin=ALLBUT,@railsYamlRegions keepend oneline
      syn region  railsYamlBlock	    matchgroup=railsYamlDelimiter start="<%%\@!" end="%>" contains=@rubyTop	       containedin=ALLBUT,@railsYamlRegions
      syn region  railsYamlExpression matchgroup=railsYamlDelimiter start="<%="    end="%>" contains=@rubyTop	       containedin=ALLBUT,@railsYamlRegions
      syn region  railsYamlComment    matchgroup=railsYamlDelimiter start="<%#"    end="%>" contains=rubyTodo,@Spell containedin=ALLBUT,@railsYamlRegions keepend
        syn match railsYamlMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' containedin=@railsErubyRegions
      hi def link railsYamlDelimiter              Delimiter
      hi def link railsYamlMethod                 railsMethod
      hi def link railsMethod                     Function
      hi def link railsYamlComment                Comment
      let b:current_syntax = "yaml"
    endif
  endif
endfunction

" }}}1

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
    return s:RailsUnderscore(v:fname,1)
  endif
endfunction

function! s:LinePeak()
  let line = getline(line("."))
  let line = s:sub(line,'^\(.\{'.col(".").'\}\).*','\1')
  let line = s:sub(line,'\([:"'."'".']\|%[qQ]\=[[({<]\)\=\f*$','')
  return line
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
  if a:0 == 1
    " Get the text before the filename under the cursor.
    " We'll cheat and peak at this in a bit
    let line = s:LinePeak()
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
" Mappings/Abbreviations {{{1

function! s:Mappings()
  map <buffer> <silent> <Plug>RailsAlternate :Alternate<CR>
  if g:rails_mappings
    if !hasmapto("<Plug>RailsAlternate")
      map <buffer> <LocalLeader>ra <Plug>RailsAlternate
    endif
  endif
endfunction

function! <SID>RailsSelectiveExpand(pat,good,default,...)
  if a:0 > 0
    let nd = a:1
  else
    let nd = ""
  endif
  let c = nr2char(getchar(0))
  let good = s:gsub(a:good,'\\<Esc>',"\<Esc>")
  if c == "" || c == "\t"
    return good.(a:0 ? " ".a:1 : '')
  elseif c =~ a:pat
    return good.c.(a:0 ? a:1 : '')
"    return s:sub(good,' $','').c
"    if good =~ '@'
"      return s:sub(good,"@",c)
"    else
"      return good.c
"    endif
  else
    return a:default.c
  endif
endfunction

function! <SID>DiscretionaryComma()
  let c = nr2char(getchar(0))
  if c =~ '[\r,;]'
    return c
  else
    return ",".c
  endif
endfunction

function! <SID>TheMagicC()
  let l = s:LinePeak()
  if l =~ '\<find\s*\((\|:first,\|:all,\)'
    return <SID>RailsSelectiveExpand('..',':conditions => ',':c')
  elseif l =~ '\<render\s\+:partial\s\+=>\s*'
    return <SID>RailsSelectiveExpand('..',':collection => ',':c')
  else
    return <SID>RailsSelectiveExpand('..',':controller => ',':c')
  endif
endfunction

function! s:AddSelectiveExpand(abbr,pat,expn,...)
  let pat = s:gsub(a:pat,"'","'.\"'\".'")
  exe "iabbr <buffer> <silent> ".a:abbr." <C-R>=<SID>RailsSelectiveExpand('".pat."','".a:expn."','".a:abbr.(a:0 ? "','".a:1 : '')."')<CR>"
endfunction

function! s:AddTabExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'..',a:expn)
endfunction

function! s:AddBracketExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'[[]',a:expn)
endfunction

function! s:AddParenExpand(abbr,expn,...)
  if a:0
    call s:AddSelectiveExpand(a:abbr,'(',a:expn,a:1)
  else
    call s:AddSelectiveExpand(a:abbr,'(',a:expn)
  endif
endfunction

function! s:Abbreviations()
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
      iabbr render_partial render :partial =>
      iabbr render_action render :action =>
      iabbr render_text render :text =>
      iabbr render_file render :file =>
      iabbr render_template render :template =>
      iabbr <silent> render_nothing render :nothing => true<C-R>=<SID>DiscretionaryComma()<CR>
      iabbr <silent> render_without_layout render :layout => false<C-R>=<SID>DiscretionaryComma()<CR>
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
      " ugh, stupid POS
      " call s:AddTabExpand('mct','create_table "" do <Bar>t<Bar>\<Lt>Esc>7hi')
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
    call s:AddParenExpand('logi','logger.info','')
    call s:AddParenExpand('fi','find','')
  endif
endfunction
" }}}1

call s:InitPlugin()

let &cpo = cpo_save

" vim:set sw=2 sts=2:
