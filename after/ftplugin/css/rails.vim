try
  if expand('%:p') =~# '[\/]assets[\/]'
    call rails#sprockets_setup('css')
  endif
  if expand('%:p') =~# '[\/]javascript[\/]packs[\/]'
    call rails#webpacker_setup('css')
  endif
catch /^E117:/
endtry
