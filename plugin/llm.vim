" vim-llm-assistant - LLM assistant for Vim
" Maintainer: Paul <paul.a.dibiase@gmail.com>
" Version: .9

if exists('g:loaded_llm_assistant')
  finish
endif
let g:loaded_llm_assistant = 1

" Default settings - can be overridden in user's vimrc
if !exists('g:llm_default_model')
  let g:llm_default_model = 'claude-3-7-sonnet-20250219'
endif

if !exists('g:llm_role')
  let g:llm_role = 'default-vim-role'
endif

if !exists('g:llm_default_adapter')
  let g:llm_default_adapter = 'aichat'
endif

" Scratch buffer temp file path (empty string means disabled)
" Set this to a file path to automatically save scratch buffer contents when saving a session
if !exists('g:llm_scratch_temp_file')
  let g:llm_scratch_temp_file = '' " Empty string means disabled by default
endif

" Default adapters to load - can be overridden in user's vimrc
if !exists('g:llm_adapters')
  let g:llm_adapters = ['aichat']  " Default adapter
endif

" Load all configured adapters
for adapter in g:llm_adapters
  let adapter_path = 'autoload/llm/adapters/' . adapter . '.vim'
  execute 'runtime ' . adapter_path
endfor

" Define commands
command! -nargs=? -complete=buffer LLM call llm#run(<q-args>)
command! -nargs=? -complete=customlist,llm#complete_models SetLLMModel call llm#set_default_model(<q-args>)
command! -nargs=? -complete=customlist,llm#complete_adapters SetLLMAdapter call llm#set_default_adapter(<q-args>)

command! -range -nargs=? LLMSnip call llm#add_snippet()
command! ViewLLMSnippets call llm#open_snippet_buffer()
command! ClearLLMSnippets call llm#clear_snippet_buffer()
command! ListLLMModels echo llm#get_available_models()
command! ListLLMAdapters echo llm#adapter#list()

" Define mappings (can be commented out if the user prefers to define their own)
" nnoremap <leader>ll :LLM<CR>

" Custom completion function for SetLLMModel
function! llm#complete_models(arglead, cmdline, cursorpos) abort
  return llm#get_available_models()
endfunction

" Custom completion function for SetLLMAdapter
function! llm#complete_adapters(arglead, cmdline, cursorpos) abort
  return llm#adapter#list()
endfunction

" Create commands for session management
command! -nargs=? -complete=customlist,llm#complete_sessions SaveLLMSession call llm#save_session(<q-args>)
command! -nargs=? -complete=customlist,llm#complete_sessions LoadLLMSession call llm#load_session(<q-args>)