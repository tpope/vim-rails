if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

function! s:reload_log() abort
  if &buftype == 'quickfix' && get(w:, 'quickfix_title') =~ '^:cgetfile'
    let cmd = 'cgetfile ' .
          \ (exists('*fnameescape') ? fnameescape(w:quickfix_title[10:-1]) : w:quickfix_title[10:-1]) .
          \ "|call setpos('.', " . string(getpos('.')) . ")"
  else
    let cmd = 'checktime'
  endif
  return cmd . "|if &l:filetype !=# 'railslog'|setfiletype railslog|endif"
endfunction

if exists('w:quickfix_title')
  runtime! ftplugin/qf.vim ftplugin/qf_*.vim ftplugin/qf/*.vim
endif
let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe')
nnoremap <buffer> <silent> R :<C-U>exe <SID>reload_log()<CR>
nnoremap <buffer> <silent> G :<C-U>exe <SID>reload_log()<Bar>exe v:count ? v:count : '$'<CR>
nnoremap <buffer> <silent> q :bwipe<CR>
let b:undo_ftplugin .= '|sil! nunmap <buffer> R|sil! nunmap <buffer> G|sil! nunmap <buffer> q'
setlocal noswapfile autoread
let b:undo_ftplugin .= '|set swapfile< autoread<'
if exists('+concealcursor')
  setlocal concealcursor=nc conceallevel=2
  let b:undo_ftplugin .= ' concealcursor< conceallevel<'
else
  let s:pos = getpos('.')
  setlocal modifiable
  silent exe '%s/\m\C\%(\e\[[0-9;]*m\|\r$\)//e' . (&gdefault ? '' : 'g')
  call setpos('.', s:pos)
endif
setlocal readonly nomodifiable
let b:undo_ftplugin .= ' noreadonly modifiable'
