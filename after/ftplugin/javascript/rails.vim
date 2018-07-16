try
  if expand('%:p') =~# '[\/]assets[\/]'
    call rails#sprockets_setup('js')
  endif
  if expand('%:p') =~# '[\/]javascript[\/]packs[\/]'
    call rails#webpacker_setup('js')
  endif
catch /^E117:/
endtry
