" vim-llm-assistant - LLM assistant for Vim
" Maintainer: Your Name <your.email@example.com>
" Version: 1.0

if exists('g:loaded_llm_assistant')
  finish
endif
let g:loaded_llm_assistant = 1

" Default settings - can be overridden in user's vimrc
if !exists('g:llm_default_model')
  let g:llm_default_model = 'Alfred:o3-mini'
endif

if !exists('g:llm_role')
  let g:llm_role = 'default-vim-role'
endif

" Define commands
command! -nargs=? -complete=buffer LLM call llm#run(<q-args>)
command! -nargs=? -complete=customlist,llm#complete_models SetLLMModel call llm#set_default_model(<q-args>)
command! ListLLMModels echo llm#get_available_models()

" Define mappings (can be commented out if the user prefers to define their own)
" nnoremap <leader>ll :LLM<CR>
" nnoremap <leader>lm :call llm#run('', 1)<CR>

" Custom completion function for SetLLMModel
function! llm#complete_models(arglead, cmdline, cursorpos) abort
  return llm#get_available_models()
endfunction