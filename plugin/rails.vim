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

runtime! autoload/rails.vim

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
