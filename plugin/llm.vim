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

" Default adapters to load - can be overridden in user's vimrc
if !exists('g:llm_adapters')
  let g:llm_adapters = ['aichat']  " Default adapter
endif

" Enable async processing if supported
if !exists('g:llm_use_async')
  let g:llm_use_async = has('job') && has('timers')
endif

" Session Status Logger settings
if !exists('g:llm_session_log_enabled')
  let g:llm_session_log_enabled = 1
endif

if !exists('g:llm_session_log_dir')
  let g:llm_session_log_dir = ''  " empty = ~/.local/share/vim-llm-assistant/logs
endif

if !exists('g:llm_status_tui_height')
  let g:llm_status_tui_height = 15
endif

if !exists('g:llm_status_tui_script')
  let g:llm_status_tui_script = ''  " empty = auto-detect from plugin directory
endif

" Optional: user-defined notification hook, called after :LLM or :LLMFile completes.
" Define a function in your vimrc and assign it as a Funcref:
"   let g:Llm_notify_func = function('MyLLMNotify')
" Your function receives one argument — a dict: {'prompt': '...', 'model': '...'}
" No default is set; this feature is entirely opt-in.

" Load all configured adapters
for adapter in g:llm_adapters
  let adapter_path = 'autoload/llm/adapters/' . adapter . '.vim'
  execute 'runtime ' . adapter_path
endfor

" Define commands
command! -nargs=? -complete=buffer LLM call llm#run(<q-args>)
command! -nargs=+ -complete=file LLMFile call llm#run_with_files(<q-args>)
command! -nargs=? -complete=customlist,llm#complete_models SetLLMModel call llm#set_default_model(<q-args>)
command! -nargs=? -complete=customlist,llm#complete_adapters SetLLMAdapter call llm#set_default_adapter(<q-args>)

command! -range -nargs=? LLMSnip call llm#add_snippet()
command! ViewLLMSnippets call llm#open_snippet_buffer()
command! ClearLLMSnippets call llm#clear_snippet_buffer()
command! ListLLMModels echo llm#get_available_models()
command! ListLLMAdapters echo llm#adapter#list()

" Job management commands
command! -nargs=? StopLLMJob call llm#stop_job(<args>)
command! ListLLMJobs call llm#list_jobs()

" Session status logger commands
command! -nargs=? LLMStatus call llm#open_status_tui(<q-args>)
command! LLMStatusClose call llm#close_status_tui()
command! LLMLog execute 'edit ' . llm#session_log#log_dir()
command! LLMLogClear call delete(llm#session_log#log_dir() . '/*.jsonl')

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
