local vim = vim
local api = vim.api
local util = require 'completion.util'
local complete = require 'completion.complete'
local chain_completion = require 'completion.chain_completion'
local lsp = require 'source.lsp'
local snippet = require 'source.snippet'
local path = require 'source.path'

local M = {}

local complete_items_map = {
  ['lsp'] = {
    trigger = lsp.triggerFunction,
    callback = lsp.getCallback,
    item = lsp.getCompletionItems
  },
  ['snippet'] = {
    item = snippet.getCompletionItems
  },
  ['path'] = {
    item = path.getCompletionItems,
    callback = path.getCallback,
    trigger = path.triggerFunction,
    trigger_character = {'/'}
  },
}

M.prefixLength = 0
M.chain_complete_index = 1
M.stop_complete = false


------------------------------------------------------------------------
--                           local function                           --
------------------------------------------------------------------------

local getTriggerCharacter = function()
  local triggerCharacter = {}
  local complete_source = M.chain_complete_list[M.chain_complete_index]
  if complete_source ~= nil and vim.fn.has_key(complete_source, "complete_items") > 0 then
    for _, item in ipairs(complete_source.complete_items) do
      local complete_items = complete_items_map[item]
      if complete_items ~= nil and complete_items.trigger_character ~= nil then
        for _,val in ipairs(complete_items.trigger_character) do
          table.insert(triggerCharacter, val)
        end
      end
    end
  end
  return triggerCharacter
end

local triggerCurrentCompletion = function(manager, bufnr, line_to_cursor, prefix, textMatch, force)
  -- avoid rebundant calling of completion
  if manager.insertChar == false then return end

  -- get current completion source
  M.chain_complete_list = chain_completion.getChainCompleteList(api.nvim_buf_get_option(0, 'filetype'))
  M.chain_complete_length = #M.chain_complete_list
  local complete_source = M.chain_complete_list[M.chain_complete_index]
  if complete_source == nil then return end

  -- handle source trigger character and user defined trigger character
  local source_trigger_character = getTriggerCharacter(complete_source)
  local triggered
  triggered = util.checkTriggerCharacter(line_to_cursor, source_trigger_character) or
              util.checkTriggerCharacter(line_to_cursor, vim.g.completion_trigger_character)

  if complete_source.complete_items ~= nil then
    for _, source in ipairs(complete_source.complete_items) do
      if source == 'lsp' and vim.lsp.buf_get_clients() ~= nil then
        for _, value in pairs(vim.lsp.buf_get_clients()) do
          if value.server_capabilities.completionProvider == nil then
            break
          end
          triggered = triggered or util.checkTriggerCharacter(line_to_cursor,
            value.server_capabilities.completionProvider.triggerCharacters)
        end
        break
      end
    end
  end

  -- handle user defined only triggered character
  if complete_source['triggered_only'] ~= nil then
    local triggered_only = util.checkTriggerCharacter(line_to_cursor, complete_source['triggered_only'])
    if not triggered_only then
      if manager.autoChange then
        manager.changeSource = true
      end
      return
    end
  end

  local length = vim.g.completion_trigger_keyword_length
  if #prefix < length and not triggered and not force then
    return
  end
  if triggered then
    M.chain_complete_index = 1
  end

  complete.performComplete(complete_source, complete_items_map, manager, bufnr, prefix, textMatch)
end

local getPositionParam = function()
  local bufnr = api.nvim_get_current_buf()
  local pos = api.nvim_win_get_cursor(0)
  local line = api.nvim_get_current_line()
  local line_to_cursor = line:sub(1, pos[2])
  return bufnr, line_to_cursor
end

------------------------------------------------------------------------
--                          member function                           --
------------------------------------------------------------------------

-- Activate when manually triggered completion or manually changing completion source
function M.triggerCompletion(force, manager)
  if force then
    M.chain_complete_index = 1
  end
  local bufnr, line_to_cursor = getPositionParam()
  local textMatch = vim.fn.match(line_to_cursor, '\\k*$')
  local prefix = line_to_cursor:sub(textMatch+1)
  manager.insertChar = true
  -- force is used when manually trigger, so it doesn't repect the trigger word length
  triggerCurrentCompletion(manager, bufnr, line_to_cursor, prefix, textMatch, force)
end

-- Handler for auto completion
function M.autoCompletion(manager)
  local bufnr, line_to_cursor = getPositionParam()
  local textMatch = vim.fn.match(line_to_cursor, '\\k*$')
  local prefix = line_to_cursor:sub(textMatch+1)
  local length = vim.g.completion_trigger_keyword_length

  -- reset completion when deleting character in insert mode
  if #prefix < M.prefixLength and vim.fn.pumvisible() == 0 then
    M.chain_complete_index = 1
    -- api.nvim_input("<c-g><c-g>")
    if vim.g.completion_trigger_on_delete == 1 then
      M.triggerCompletion(false, manager)
    end
    M.stop_complete = false
  end
  M.prefixLength = #prefix

  -- force reset chain completion if entering a new word
  if (#prefix < length) then
    M.chain_complete_index = 1
    M.stop_complete = false
    manager.changeSource = false
  end

  -- stop auto completion when all sources return no complete-items
  if M.stop_complete == true then return end

  triggerCurrentCompletion(manager, bufnr, line_to_cursor, prefix, textMatch)

end

-- provide api for custom complete items
function M.addCompleteItems(key, complete_item)
  complete_items_map[key] = complete_item
end

function M.nextCompletion()
  if M.chain_complete_index ~= #M.chain_complete_list then
    M.chain_complete_index = M.chain_complete_index + 1
  else
    M.chain_complete_index = 1
  end
end

function M.prevCompletion()
  if M.chain_complete_index ~= 1 then
    M.chain_complete_index = M.chain_complete_index - 1
  else
    M.chain_complete_index = #M.chain_complete_list
  end
end


function M.checkHealth()
  chain_completion.checkHealth(complete_items_map)
end

return M
