if exists('b:current_syntax')
  finish
endif

if has('conceal')
  syn match railslogEscape      '\e\[[0-9;]*m' conceal
  syn match railslogEscapeMN    '\e\[[0-9;]*m' conceal nextgroup=railslogModelNum,railslogEscapeMN skipwhite contained
else
  syn match railslogEscape      '\e\[[0-9;]*m'
  syn match railslogEscapeMN    '\e\[[0-9;]*m' nextgroup=railslogModelNum,railslogEscapeMN skipwhite contained
endif
syn match   railslogQfFileName  "^[^()|]*|\@=" nextgroup=railslogQfSeparator
syn match   railslogQfSeparator "|" nextgroup=railslogQfLineNr contained
syn match   railslogQfLineNr    "[^|]*" contained contains=railslogQfError
syn match   railslogQfError     "error" contained
syn match   railslogRender      '\%(\%(^\||\)\s*\%(\e\[[0-9;]*m\)\=\)\@<=\%(Started\|Processing\|Rendering\|Rendered\|Redirected\|Completed\)\>'
syn match   railslogComment     '\%(^\|[]|]\)\@<=\s*# .*'
syn match   railslogModel       '\%(\%(^\|[]|]\)\s*\%(\e\[[0-9;]*m\)*\)\@<=\%(CACHE SQL\|CACHE\|SQL\)\>' skipwhite nextgroup=railslogModelNum,railslogEscapeMN
syn match   railslogModel       '\%(\%(^\|[]|]\)\s*\%(\e\[[0-9;]*m\)*\)\@<=\%(CACHE \)\=\u\%(\w\|:\)* \%(Load\%( Including Associations\| IDs For Limited Eager Loading\)\=\|Columns\|Exists\|Count\|Create\|Update\|Destroy\|Delete all\)\>' skipwhite nextgroup=railslogModelNum,railslogEscapeMN
syn region  railslogModelNum    start='(' end=')' contains=railslogNumber contained skipwhite
syn match   railslogActiveJob   '\[ActiveJob\]'hs=s+1,he=e-1 nextgroup=railslogJobScope skipwhite
syn match   railslogJobScope    '\[\u\%(\w\|:\)*\]' contains=railslogJobName contained
syn match   railslogJob         '\%(\%(^\|[\]|]\)\s*\%(\e\[[0-9;]*m\)*\)\@<=\%(Enqueued\|Performing\|Performed\)\>' skipwhite nextgroup=railslogJobName
syn match   railslogJobName     '\<\u\%(\w\|:\)*\>' contained
syn match   railslogNumber      '\<\d\+%'
syn match   railslogNumber      '[ (]\@<=\<\d\+\.\d\+\>\.\@!'
syn match   railslogNumber      '[ (]\@<=\<\d\+\%(\.\d\+\)\=ms\>'
syn region  railslogString      start='"' skip='\\"' end='"' oneline contained
syn region  railslogHash        start='{' end='}' oneline contains=railslogHash,railslogString
syn match   railslogIP          '\<\d\{1,3\}\%(\.\d\{1,3}\)\{3\}\>'
syn match   railslogIP          '\<\%(\x\{1,4}:\)\+\%(:\x\{1,4}\)\+\>\|\S\@<!:\%(:\x\{1,4}\)\+\>\|\<\%(\x\{1,4}:\)\+\%(:\S\@!\|\x\{1,4}\>\)'
syn match   railslogTimestamp   '\<\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\%( [+-]\d\d\d\d\| UTC\)\=\>'
syn match   railslogSessionID   '\<\x\{32\}\>'
syn match   railslogUUID        '\<\x\{8\}-\x\{4\}-\x\{4\}-\x\{4\}-\x\{12\}\>'
syn match   railslogIdentifier  '\%(^\||\)\@<=\s*\%(Session ID\|Parameters\|Unpermitted parameters\)\ze:'
syn match   railslogSuccess     '\<2\d\d\%( \u\w*\)\+\>'
syn match   railslogRedirect    '\<3\d\d\%( \u\w*\)\+\>'
syn match   railslogError       '\<[45]\d\d\%( \u\w*\)\+\>'
syn match   railslogDeprecation '\<DEPRECATION WARNING\>'
syn keyword railslogHTTP        OPTIONS GET HEAD POST PUT PATCH DELETE TRACE CONNECT

hi def link railslogQfFileName  Directory
hi def link railslogQfLineNr    LineNr
hi def link railslogQfError     Error
hi def link railslogEscapeMN    railslogEscape
hi def link railslogEscape      Ignore
hi def link railslogComment     Comment
hi def link railslogRender      Keyword
hi def link railslogModel       Type
hi def link railslogJob         Repeat
hi def link railslogJobName     Structure
hi def link railslogNumber      Float
hi def link railslogString      String
hi def link railslogSessionID   Constant
hi def link railslogUUID        Constant
hi def link railslogIdentifier  Identifier
hi def link railslogRedirect    railslogSuccess
hi def link railslogSuccess     Special
hi def link railslogDeprecation railslogError
hi def link railslogError       Error
hi def link railslogHTTP        Special
