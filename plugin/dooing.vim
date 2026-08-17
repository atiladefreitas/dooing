if exists('g:loaded_dooing') | finish | endif
let g:loaded_dooing = 1

lua require('dooing').bootstrap()
