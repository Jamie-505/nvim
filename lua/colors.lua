local M = {}

M.color_modules = {}

M.add_color_module = function(module_name, set_colors_function)
  M.color_modules[module_name] = set_colors_function
end

M.add_and_set_color_module = function(module_name, set_colors_function)
  M.color_modules[module_name] = set_colors_function
  M.color_modules[module_name]()
end

M.get_color_module = function(module_name)
  return M.color_modules[module_name]
end

M.set_colors = function(module_name)
  local module = M.color_modules[module_name]
  if module ~= nil then
    module()
  end
end

return M
