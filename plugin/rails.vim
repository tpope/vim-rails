" rails.vim - Detect a rails application
" Author:       Tim Pope <vimNOSPAM@tpope.info>
" GetLatestVimScripts: 1567 1 :AutoInstall: rails.vim
" URL:          http://rails.vim.tpope.net/

" Install this file as plugin/rails.vim.  See doc/rails.txt for details. (Grab
" it from the URL above if you don't have it.)  To access it from Vim, see
" :help add-local-help (hint: :helptags ~/.vim/doc) Afterwards, you should be
" able to do :help rails

" ============================================================================

" Exit quickly when:
" - this plugin was already loaded (or disabled)
" - when 'compatible' is set
if &cp || (exists("g:loaded_rails") && g:loaded_rails) && !(exists("g:rails_debug") && g:rails_debug)
  finish
endif
let g:loaded_rails = 1

" Utility Functions {{{1

function! s:error(str)
  echohl ErrorMsg
  echomsg a:str
  echohl None
  let v:errmsg = a:str
endfunction

function! s:autoload(...)
  if !exists("g:autoloaded_rails")
    runtime! autoload/rails.vim
  endif
  if exists("g:autoloaded_rails")
    if a:0
      exe a:1
    endif
    return 1
  endif
  if !exists("g:rails_no_autoload_warning")
    let g:rails_no_autoload_warning = 1
    call s:error("Disabling rails.vim: autoload/rails.vim is missing")
  endif
  return ""
endfunction

" }}}1
" Configuration {{{

function! s:SetOptDefault(opt,val)
  if !exists("g:".a:opt)
    let g:{a:opt} = a:val
  endif
endfunction

call s:SetOptDefault("rails_level",3)
call s:SetOptDefault("rails_statusline",1)
call s:SetOptDefault("rails_syntax",1)
call s:SetOptDefault("rails_mappings",1)
call s:SetOptDefault("rails_abbreviations",1)
call s:SetOptDefault("rails_expensive",1+0*(has("win32")||has("win32unix")))
call s:SetOptDefault("rails_dbext",g:rails_expensive)
call s:SetOptDefault("rails_subversion",0)
call s:SetOptDefault("rails_default_file","README")
call s:SetOptDefault("rails_default_database","")
call s:SetOptDefault("rails_root_url",'http://localhost:3000/')
call s:SetOptDefault("rails_modelines",1)
call s:SetOptDefault("rails_menu",1)
call s:SetOptDefault("rails_gnu_screen",1)
call s:SetOptDefault("rails_history_size",5)
call s:SetOptDefault("rails_debug",0)
call s:SetOptDefault("rails_generators","controller\nintegration_test\nmailer\nmigration\nmodel\nobserver\nplugin\nresource\nscaffold\nsession_migration")
call s:SetOptDefault("rails_rake_tasks","db:charset\ndb:collation\ndb:create\ndb:create:all\ndb:drop\ndb:drop:all\ndb:fixtures:identify\ndb:fixtures:load\ndb:migrate\ndb:reset\ndb:rollback\ndb:schema:dump\ndb:schema:load\ndb:sessions:clear\ndb:sessions:create\ndb:structure:dump\ndb:test:clone\ndb:test:clone_structure\ndb:test:prepare\ndb:test:purge\ndb:version\ndoc:app\ndoc:clobber_app\ndoc:clobber_plugins\ndoc:clobber_rails\ndoc:plugins\ndoc:rails\ndoc:reapp\ndoc:rerails\nlog:clear\nnotes\nnotes:fixme\nnotes:optimize\nnotes:todo\nrails:freeze:edge\nrails:freeze:gems\nrails:unfreeze\nrails:update\nrails:update:configs\nrails:update:javascripts\nrails:update:scripts\nroutes\nstats\ntest\ntest:functionals\ntest:integration\ntest:plugins\ntest:recent\ntest:uncommitted\ntest:units\ntmp:cache:clear\ntmp:clear\ntmp:create\ntmp:pids:clear\ntmp:sessions:clear\ntmp:sockets:clear")
if g:rails_dbext
  if exists("g:loaded_dbext") && executable("sqlite3") && ! executable("sqlite")
    " Since dbext can't find it by itself
    call s:SetOptDefault("dbext_default_SQLITE_bin","sqlite3")
  endif
endif

" }}}1
" Detection {{{1

function! s:escvar(r)
  let r = fnamemodify(a:r,':~')
  let r = substitute(r,'\W','\="_".char2nr(submatch(0))."_"','g')
  let r = substitute(r,'^\d','_&','')
  return r
endfunction

function! s:Detect(filename)
  let fn = substitute(fnamemodify(a:filename,":p"),'\c^file://','','')
  if fn =~ '[\/]config[\/]environment\.rb$'
    return s:BufInit(strpart(fn,0,strlen(fn)-22))
  endif
  if isdirectory(fn)
    let fn = fnamemodify(fn,":s?[\/]$??")
  else
    let fn = fnamemodify(fn,':s?\(.*\)[\/][^\/]*$?\1?')
  endif
  let ofn = ""
  let nfn = fn
  while nfn != ofn && nfn != ""
    if exists("s:_".s:escvar(nfn))
      return s:BufInit(nfn)
    endif
    let ofn = nfn
    let nfn = fnamemodify(nfn,':h')
  endwhile
  let ofn = ""
  while fn != ofn
    if filereadable(fn . "/config/environment.rb")
      return s:BufInit(fn)
    endif
    let ofn = fn
    let fn = fnamemodify(ofn,':s?\(.*\)[\/]\(app\|config\|db\|doc\|lib\|log\|public\|script\|spec\|test\|tmp\|vendor\)\($\|[\/].*$\)?\1?')
  endwhile
  return 0
endfunction

function! s:BufInit(path)
  let s:_{s:escvar(a:path)} = 1
  if s:autoload()
    return RailsBufInit(a:path)
  endif
endfunction

" }}}1
" Initialization {{{1

augroup railsPluginDetect
  autocmd!
  autocmd BufNewFile,BufRead * call s:Detect(expand("<afile>:p"))
  autocmd VimEnter * if expand("<amatch>") == "" && !exists("b:rails_root") | call s:Detect(getcwd()) | endif | if exists("b:rails_root") | silent doau User BufEnterRails | endif
  autocmd FileType netrw if !exists("b:rails_root") | call s:Detect(expand("<afile>:p")) | endif | if exists("b:rails_root") | silent doau User BufEnterRails | endif
  autocmd BufEnter * if exists("b:rails_root")|silent doau User BufEnterRails|endif
  autocmd BufLeave * if exists("b:rails_root")|silent doau User BufLeaveRails|endif
  autocmd FileType railslog if s:autoload()|call RailslogSyntax()|endif
augroup END

command! -bar -bang -nargs=* -complete=dir Rails :if s:autoload()|call RailsNewApp(<bang>0,<f-args>)|endif

" }}}1
" Menus {{{1

if !exists("g:rails_tabstop") && !(g:rails_menu && has("menu"))
  finish
endif

function! s:sub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! s:CreateMenus() abort
  if exists("g:rails_installed_menu") && g:rails_installed_menu != ""
    exe "aunmenu ".s:gsub(g:rails_installed_menu,'\&','')
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
      exe menucmd.g:rails_installed_menu.'.-PSep- :'
      exe menucmd.g:rails_installed_menu.'.&Related\ file\	:R\ /\ Alt+] :R<CR>'
      exe menucmd.g:rails_installed_menu.'.&Alternate\ file\	:A\ /\ Alt+[ :A<CR>'
      exe menucmd.g:rails_installed_menu.'.&File\ under\ cursor\	Ctrl+Enter :Rfind<CR>'
    else
      let menucmd = 'anoremenu <script> '
      exe menucmd.g:rails_installed_menu.'.-PSep- :'
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
    let tasks = g:rails_rake_tasks
    while tasks != ''
      let task = matchstr(tasks,'.\{-\}\ze\%(\n\|$\)')
      let tasks = s:sub(tasks,'.{-}%(\n|$)','')
      exe menucmd.g:rails_installed_menu.'.Rake\ &tasks\	:Rake.'.s:sub(s:sub(task,'^[^:]*$','&:all'),':','.').' :Rake '.task.'<CR>'
    endwhile
    let tasks = g:rails_generators
    while tasks != ''
      let task = matchstr(tasks,'.\{-\}\ze\%(\n\|$\)')
      let tasks = s:sub(tasks,'.{-}%(\n|$)','')
      exe menucmd.'<silent> '.g:rails_installed_menu.'.&Generate\	:Rgen.'.s:gsub(task,'_','\\ ').' :call <SID>menuprompt("Rgenerate '.task.'","Arguments for script/generate '.task.': ")<CR>'
      exe menucmd.'<silent> '.g:rails_installed_menu.'.&Destroy\	:Rdestroy.'.s:gsub(task,'_','\\ ').' :call <SID>menuprompt("Rdestroy '.task.'","Arguments for script/destroy '.task.': ")<CR>'
    endwhile
    exe menucmd.g:rails_installed_menu.'.&Server\	:Rserver.&Start\	:Rserver :Rserver<CR>'
    exe menucmd.g:rails_installed_menu.'.&Server\	:Rserver.&Force\ start\	:Rserver! :Rserver!<CR>'
    exe menucmd.g:rails_installed_menu.'.&Server\	:Rserver.&Kill\	:Rserver!\ - :Rserver! -<CR>'
    exe menucmd.'<silent> '.g:rails_installed_menu.'.&Evaluate\ Ruby\.\.\.\	:Rp :call <SID>menuprompt("Rp","Code to execute and output: ")<CR>'
    exe menucmd.g:rails_installed_menu.'.&Console\	:Rconsole :Rconsole<CR>'
    exe menucmd.g:rails_installed_menu.'.&Preview\	:Rpreview :Rpreview<CR>'
    exe menucmd.g:rails_installed_menu.'.&Log\ file\	:Rlog :Rlog<CR>'
    exe s:sub(menucmd,'anoremenu','vnoremenu').' <silent> '.g:rails_installed_menu.'.E&xtract\ as\ partial\	:Rextract :call <SID>menuprompt("'."'".'<,'."'".'>Rextract","Partial name (e.g., template or /controller/template): ")<CR>'
    exe menucmd.g:rails_installed_menu.'.&Migration\ writer\	:Rinvert :Rinvert<CR>'
    exe menucmd.'         '.g:rails_installed_menu.'.-HSep- :'
    exe menucmd.'<silent> '.g:rails_installed_menu.'.&Help\	:help\ rails :if <SID>autoload()<Bar>exe RailsHelpCommand("")<Bar>endif<CR>'
    exe menucmd.'<silent> '.g:rails_installed_menu.'.Abo&ut\	 :if <SID>autoload()<Bar>exe RailsHelpCommand("about")<Bar>endif<CR>'
    let g:rails_did_menus = 1
    call s:ProjectMenu()
    call s:menuBufLeave()
    if exists("b:rails_root")
      call s:menuBufEnter()
    endif
  endif
endfunction

function! s:ProjectMenu()
  if exists("g:rails_did_menus") && g:rails_history_size > 0
    if !exists("g:RAILS_HISTORY")
      let g:RAILS_HISTORY = ""
    endif
    let history = g:RAILS_HISTORY
    let menu = s:gsub(g:rails_installed_menu,'\&','')
    silent! exe "aunmenu <script> ".menu.".Projects"
    let dots = s:gsub(menu,'[^.]','')
    exe 'anoremenu <script> <silent> '.(exists("$CREAM") ? '87' : '').dots.'.100 '.menu.'.Pro&jects.&New\.\.\.\	:Rails :call <SID>menuprompt("Rails","New application path and additional arguments: ")<CR>'
    exe 'anoremenu <script> '.menu.'.Pro&jects.-FSep- :'
    while history =~ '\n'
      let proj = matchstr(history,'^.\{-\}\ze\n')
      let history = s:sub(history,'^.{-}\n','')
      exe 'anoremenu <script> '.menu.'.Pro&jects.'.s:gsub(proj,'[.\\ ]','\\&').' :e '.s:gsub(proj."/".g:rails_default_file,'[ !%#]','\\&')."<CR>"
    endwhile
  endif
endfunction

function! s:menuBufEnter()
  if exists("g:rails_installed_menu") && g:rails_installed_menu != ""
    let menu = s:gsub(g:rails_installed_menu,'\&','')
    exe 'amenu enable '.menu.'.*'
    if RailsFileType() !~ '^view\>'
      exe 'vmenu disable '.menu.'.Extract\ as\ partial'
    endif
    if RailsFileType() !~ '^\%(db-\)\=migration$' || RailsFilePath() =~ '\<db/schema\.rb$'
      exe 'amenu disable '.menu.'.Migration\ writer'
    endif
    call s:ProjectMenu()
  endif
endfunction

function! s:menuBufLeave()
  if exists("g:rails_installed_menu") && g:rails_installed_menu != ""
    let menu = s:gsub(g:rails_installed_menu,'\&','')
    exe 'amenu disable '.menu.'.*'
    exe 'amenu enable  '.menu.'.Help\	'
    exe 'amenu enable  '.menu.'.About\	'
    exe 'amenu enable  '.menu.'.Projects'
  endif
endfunction

function! s:menuprompt(vimcmd,prompt)
  let res = inputdialog(a:prompt,'','!!!')
  if res == '!!!'
    return ""
  endif
  exe a:vimcmd." ".res
endfunction

function! s:findschema()
  let env = exists('$RAILS_ENV') ? $RAILS_ENV : "development"
  if filereadable(b:rails_root."/db/schema.rb")
    edit `=b:rails_root.'/db/schema.rb'`
  elseif filereadable(b:rails_root.'/db/'.env.'_structure.sql')
    edit `=b:rails_root.'/db/'.env.'_structure.sql'`
  else
    return s:error("Schema not found: try :Rake db:schema:dump")
  endif
endfunction

call s:CreateMenus()

augroup railsPluginMenu
  autocmd!
  autocmd User BufEnterRails call s:menuBufEnter()
  autocmd User BufLeaveRails call s:menuBufLeave()
  " g:RAILS_HISTORY hasn't been set when s:InitPlugin() is called.
  autocmd VimEnter *         call s:ProjectMenu()
augroup END

" }}}1
" Tab Hacks {{{1

if !exists("g:rails_tabstop")
  finish
endif

function! s:tabstop()
  if !exists("b:rails_root")
    return 0
  elseif &filetype !~ '^\%(ruby\|eruby\|haml\|dryml\|liquid\|html\|css\|sass\|yaml\|javascript\)$'
    return 0
  elseif exists("b:rails_tabstop")
    return b:rails_tabstop
  elseif exists("g:rails_tabstop")
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
      lockmarks retab!
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
    let s:retab_in_process = 1
    let &l:tabstop = 2
    setlocal expandtab
    let line = line('.')
    lockmarks retab
    lockmarks exe line
    let &l:tabstop = ts
  endif
endfunction

augroup railsPluginTabstop
  autocmd!
  autocmd BufWritePost,BufReadPost * call s:breaktabs()
  autocmd BufWritePre              * call s:fixtabs()
augroup END

" }}}1
" vim:set sw=2 sts=2:
