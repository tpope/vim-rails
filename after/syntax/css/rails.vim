if expand('%:p') !~# '[\/]\%(app\|lib\|vendor\)[\/]assets[\/]'
  finish
endif

call rails#sprockets_syntax()
