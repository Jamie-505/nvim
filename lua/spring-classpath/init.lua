-- Gradle → Spring Boot language server classpath, for projects without jdtls
-- (the Kotlin projects; ticket 06). Implements the server's classpath-listener
-- protocol (vscode-spring-boot 2.2.0) from a Gradle export instead of JDT-LS:
--
-- - `sts/addClasspathListener`: answer, then deliver one classpath event per
--   Gradle JVM project through the server's callback command
-- - the export (gradle/spring-classpath.init.gradle) is a snapshot in
--   stdpath('state'), re-exported before serving when a build file is newer;
--   `:SpringClasspathRefresh` re-exports and re-delivers on demand
-- - Java-data requests (`sts/javaType`, ...) get an explicit null without jdtls
--   instead of an RPC error
-- When a jdtls client serves the same root, everything is left to jdtls.
local M = {}

M.init_script = vim.fn.stdpath('config') .. '/gradle/spring-classpath.init.gradle'

--- client id → { callback = command id, root = dir }
local listeners = {}
--- root → { callbacks waiting for a running export }
local exporting = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Spring classpath' })
end

local function snapshot_path(root)
  local dir = vim.fn.stdpath('state') .. '/spring-classpath'
  vim.fn.mkdir(dir, 'p')
  return dir .. '/' .. vim.fs.basename(root) .. '-' .. vim.fn.sha256(root):sub(1, 8) .. '.json'
end
M.snapshot_path = snapshot_path

local function read_json(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local ok, data = pcall(vim.json.decode, f:read('*a'))
  f:close()
  return ok and data or nil
end

local function mtime(path)
  local st = path and vim.uv.fs_stat(path)
  return st and st.mtime.sec or nil
end

--- the build file newer than the snapshot, if any
function M.newer_build_file(root, snap)
  local at = mtime(snapshot_path(root))
  if not at then
    return 'no snapshot'
  end
  local files = {
    M.init_script,
    root .. '/settings.gradle.kts',
    root .. '/settings.gradle',
    root .. '/gradle.properties',
    root .. '/gradle/libs.versions.toml',
    root .. '/build.gradle.kts',
    root .. '/build.gradle',
  }
  for _, m in ipairs(snap and snap.modules or {}) do
    table.insert(files, m.buildFile)
  end
  for _, f in ipairs(files) do
    local t = mtime(f)
    if t and t > at then
      return f
    end
  end
end

function M.has_jdtls(root)
  for _, c in ipairs(vim.lsp.get_clients({ name = 'jdtls' })) do
    if c.root_dir == root then
      return true
    end
  end
  return false
end

local function gradlew_for(root)
  local wrapper = root .. '/gradlew'
  return vim.uv.fs_stat(wrapper) and wrapper or 'gradle'
end

--- Export (or reuse) the snapshot; `cb(snap, err)` on the main loop.
--- @param force? boolean re-export even when current
function M.snapshot(root, cb, force)
  local path = snapshot_path(root)
  local snap = read_json(path)
  if snap and not force and not M.newer_build_file(root, snap) then
    return cb(snap)
  end
  if exporting[root] then
    table.insert(exporting[root], cb)
    return
  end
  exporting[root] = { cb }
  local tmp = path .. '.tmp'
  os.remove(tmp)
  local log = path:gsub('%.json$', '.log')
  notify('Exporting the Gradle classpath for the Spring server…')
  local argv = {
    gradlew_for(root),
    '-q',
    '-I',
    M.init_script,
    '-Pnvim.spring.export=' .. tmp,
    '--no-configuration-cache',
    '--console=plain',
    'nvimSpringClasspath',
  }
  local proc = vim.system(argv, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      local fresh = r.code == 0 and read_json(tmp)
      local waiting = exporting[root]
      exporting[root] = nil
      local f = io.open(log, 'w')
      if f then
        f:write(table.concat(argv, ' '), '\n\n', r.stdout or '', r.stderr or '')
        f:close()
      end
      if fresh then
        os.rename(tmp, path)
        fresh.exported = os.time()
      else
        notify(
          ('Classpath export failed (exit %d)%s; log: %s'):format(r.code, snap and ', serving the previous snapshot' or '', log),
          vim.log.levels.WARN
        )
      end
      for _, w in ipairs(waiting) do
        w(fresh or snap, not fresh and ('export failed, see ' .. log) or nil)
      end
    end)
  end)
  require('kotlin-workflow.jobs').add({ pid = proc.pid, kind = 'gradle-client', label = 'Spring classpath export', root = root })
end

--- one classpath event (callback arguments) for a module
local function event(module, jdk)
  local entries, own = {}, {}
  for _, p in ipairs(module.outputDirs) do
    own[p] = true
  end
  for _, p in ipairs(module.runtimeClasspath) do
    if vim.uv.fs_stat(p) then
      table.insert(entries, { kind = 'binary', path = p, isOwn = own[p] or false, isJavaContent = true, isTest = false })
    end
  end
  local resources = {}
  for _, p in ipairs(module.resourceDirs or {}) do
    resources[p] = true
  end
  local classes = module.classesDirs or {}
  local java_out, kotlin_out = classes[1], classes[#classes]
  for _, c in ipairs(classes) do
    if c:match('/java/main$') then
      java_out = c
    elseif c:match('/kotlin/main$') then
      kotlin_out = c
    end
  end
  for _, p in ipairs(module.sourceDirs) do
    if vim.uv.fs_stat(p) then
      local output = resources[p] and module.resourcesDir or (p:match('/java$') and java_out or kotlin_out)
      -- Kotlin roots are never labelled as Java content: the server's Java
      -- indexer would parse them as Java
      table.insert(entries, {
        kind = 'source',
        path = p,
        isOwn = true,
        isJavaContent = p:match('/java$') ~= nil,
        isTest = false,
        outputFolder = output,
      })
    end
  end
  return {
    module.uri,
    module.name,
    false,
    { entries = entries, jre = { version = jdk.version, installationPath = jdk.home } },
    { type = 'gradle', buildFile = vim.uri_from_fname(module.buildFile) },
    {
      ['org.eclipse.jdt.core.compiler.compliance'] = jdk.version,
      ['org.eclipse.jdt.core.compiler.source'] = jdk.version,
      ['org.eclipse.jdt.core.compiler.codegen.targetPlatform'] = jdk.version,
    },
  }
end

local function jdk()
  local home = require('jdk').find('25') or vim.env.JAVA_HOME
  return { home = home, version = '25' }
end

--- send every module's classpath to one listening client
function M.deliver(client_id, force)
  local entry = listeners[client_id]
  local client = vim.lsp.get_client_by_id(client_id)
  if not (entry and client) then
    return
  end
  M.snapshot(entry.root, function(snap, err)
    if not snap then
      return notify('No classpath for the Spring server: ' .. tostring(err), vim.log.levels.WARN)
    end
    local pending = #snap.modules
    for _, module in ipairs(snap.modules) do
      client:request('workspace/executeCommand', {
        command = entry.callback,
        arguments = event(module, jdk()),
      }, function()
        pending = pending - 1
        if pending == 0 then
          -- the settings push makes the server re-index the projects it now knows
          vim.defer_fn(function()
            if not client:is_stopped() then
              require('spring_boot.settings').push(client)
            end
          end, 1500)
        end
      end)
    end
    entry.delivered = os.time()
    entry.modules = #snap.modules
  end, force)
end

--- `:SpringClasspathRefresh`: re-export, then re-deliver to every listener
function M.refresh()
  local any = false
  for id, entry in pairs(listeners) do
    any = true
    M.snapshot(entry.root, function()
      M.deliver(id)
    end, true)
  end
  if not any then
    local root = vim.fs.root(0, { 'gradlew', 'settings.gradle.kts', 'settings.gradle' }) or vim.fn.getcwd()
    M.snapshot(root, function(snap)
      if snap then
        notify(('Snapshot refreshed: %d modules (no Spring server listening yet)'):format(#snap.modules))
      end
    end, true)
  end
end

--- handlers and hooks merged into spring-boot.nvim's `server` config
function M.server_config()
  local java_methods = {
    'sts/javaType',
    'sts/javadocHoverLink',
    'sts/javaLocation',
    'sts/javadoc',
    'sts/javaSearchTypes',
    'sts/javaSearchPackages',
    'sts/javaSubTypes',
    'sts/javaSuperTypes',
    'sts/javaCodeComplete',
    'sts/project/gav',
  }
  local handlers = {}
  local function root_of(ctx)
    local c = vim.lsp.get_client_by_id(ctx.client_id)
    return c and c.root_dir or vim.fn.getcwd()
  end
  handlers['sts/addClasspathListener'] = function(err, params, ctx, config)
    if M.has_jdtls(root_of(ctx)) then
      return require('spring_boot.classpath').handlers()['sts/addClasspathListener'](err, params, ctx, config)
    end
    listeners[ctx.client_id] = { callback = params.callbackCommandId, root = root_of(ctx) }
    vim.schedule(function()
      M.deliver(ctx.client_id)
    end)
    return vim.NIL
  end
  handlers['sts/removeClasspathListener'] = function(err, params, ctx, config)
    if M.has_jdtls(root_of(ctx)) then
      return require('spring_boot.classpath').handlers()['sts/removeClasspathListener'](err, params, ctx, config)
    end
    listeners[ctx.client_id] = nil
    return vim.NIL
  end
  for _, method in ipairs(java_methods) do
    handlers[method] = function(err, params, ctx, config)
      if M.has_jdtls(root_of(ctx)) then
        return require('spring_boot.java_data').handlers()[method](err, params, ctx, config)
      end
      return vim.NIL
    end
  end
  return {
    handlers = handlers,
    on_init = function(client, init_result)
      require('spring_boot.util').boot_ls_init(client, init_result)
      if not M.has_jdtls(client.root_dir) then
        client:request('workspace/executeCommand', {
          command = 'sts.vscode-spring-boot.enableClasspathListening',
          arguments = { true },
        }, function() end)
      end
    end,
    on_exit = function(_, _, client_id)
      listeners[client_id] = nil
    end,
  }
end

function M.health(h)
  local root = vim.fs.root(0, { 'gradlew' }) or vim.fn.getcwd()
  local path = snapshot_path(root)
  local snap = read_json(path)
  if not snap then
    h.info('No classpath snapshot for ' .. root .. ' yet (exported when the Spring server starts)')
  else
    local newer = M.newer_build_file(root, snap)
    local line = ('Snapshot: %d modules, exported %s (%s)'):format(
      #snap.modules,
      os.date('%Y-%m-%d %H:%M', mtime(path)),
      path
    )
    if newer then
      h.warn(line, { 'Newer build file: ' .. newer .. ' — re-exported when the server restarts, or `:SpringClasspathRefresh`' })
    else
      h.ok(line)
    end
  end
  for id, entry in pairs(listeners) do
    h.info(('spring-boot client %d: %s modules delivered %s'):format(
      id,
      tostring(entry.modules or 0),
      entry.delivered and os.date('%H:%M:%S', entry.delivered) or 'not yet'
    ))
  end
end

return M
