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

" vim:set sw=2 sts=2:
