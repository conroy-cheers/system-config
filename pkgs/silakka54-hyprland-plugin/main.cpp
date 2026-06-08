#define WLR_USE_UNSTABLE

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/SharedDefs.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/helpers/Color.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <unordered_map>
#include <unistd.h>
#include <vector>

namespace {
HANDLE g_handle = nullptr;
std::atomic<bool> g_running{false};
std::atomic<int> g_renderSettles{0};
std::condition_variable g_workerCv;
std::mutex g_workerMutex;
bool g_dirty = false;
std::thread g_worker;
std::unordered_map<Desktop::View::CWindow*, std::vector<CHyprSignalListener>> g_windowListeners;

void sendRefreshPlacement() {
    const char* runtimeDir = std::getenv("XDG_RUNTIME_DIR");
    if (!runtimeDir || !*runtimeDir)
        return;

    const std::string socketPath = std::string(runtimeDir) + "/silakka54-layer-viewer.sock";
    sockaddr_un addr = {};
    addr.sun_family = AF_UNIX;
    if (socketPath.size() >= sizeof(addr.sun_path))
        return;
    std::strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);

    const int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return;

    if (connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0) {
        constexpr const char* message = "refresh-placement\n";
        const auto written = write(fd, message, std::strlen(message));
        (void)written;
    }

    close(fd);
}

void workerMain() {
    while (g_running.load()) {
        {
            std::unique_lock lock(g_workerMutex);
            g_workerCv.wait(lock, [] { return !g_running.load() || g_dirty; });
            if (!g_running.load())
                return;
            g_dirty = false;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(70));
        if (g_running.load())
            sendRefreshPlacement();
    }
}

void markDirty(bool settleOnRender = true) {
    if (settleOnRender)
        g_renderSettles.store(3);

    {
        std::lock_guard lock(g_workerMutex);
        g_dirty = true;
    }
    g_workerCv.notify_one();
}

void forgetWindow(PHLWINDOW window) {
    if (!window)
        return;
    g_windowListeners.erase(window.get());
}

void watchWindow(PHLWINDOW window) {
    if (!window || g_windowListeners.contains(window.get()))
        return;

    auto& listeners = g_windowListeners[window.get()];
    listeners.emplace_back(window->m_events.resize.listen([] { markDirty(); }));
    listeners.emplace_back(window->m_events.monitorChanged.listen([] { markDirty(); }));
    listeners.emplace_back(window->m_events.unmap.listen([] { markDirty(); }));
    listeners.emplace_back(window->m_events.hide.listen([] { markDirty(); }));
    listeners.emplace_back(window->m_events.destroy.listen([] { markDirty(); }));
}

void watchExistingWindows() {
    for (const auto& window : g_pCompositor->m_windows)
        watchWindow(window);
}

void onWindowOpen(PHLWINDOW window) {
    watchWindow(window);
    markDirty();
}

void onWindowClose(PHLWINDOW window) {
    forgetWindow(window);
    markDirty();
}

void onRenderStage(eRenderStage) {
    int remaining = g_renderSettles.load();
    if (remaining <= 0)
        return;
    if (g_renderSettles.compare_exchange_strong(remaining, remaining - 1))
        markDirty(false);
}
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    g_handle = handle;

    const std::string serverHash = __hyprland_api_get_hash();
    const std::string clientHash = __hyprland_api_get_client_hash();
    if (serverHash != clientHash) {
        HyprlandAPI::addNotification(g_handle, "[silakka54] Plugin/header API hash mismatch", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("silakka54-hyprland-plugin API hash mismatch");
    }

    g_running.store(true);
    g_worker = std::thread(workerMain);

    static auto windowActive = Event::bus()->m_events.window.active.listen([](PHLWINDOW, Desktop::eFocusReason) { markDirty(); });
    static auto windowOpen = Event::bus()->m_events.window.open.listen([](PHLWINDOW window) { onWindowOpen(window); });
    static auto windowClose = Event::bus()->m_events.window.close.listen([](PHLWINDOW window) { onWindowClose(window); });
    static auto windowFullscreen = Event::bus()->m_events.window.fullscreen.listen([](PHLWINDOW) { markDirty(); });
    static auto windowMoveToWorkspace = Event::bus()->m_events.window.moveToWorkspace.listen([](PHLWINDOW, PHLWORKSPACE) { markDirty(); });
    static auto windowUpdateRules = Event::bus()->m_events.window.updateRules.listen([](PHLWINDOW) { markDirty(); });
    static auto workspaceActive = Event::bus()->m_events.workspace.active.listen([](PHLWORKSPACE) { markDirty(); });
    static auto workspaceMoveToMonitor = Event::bus()->m_events.workspace.moveToMonitor.listen([](PHLWORKSPACE, PHLMONITOR) { markDirty(); });
    static auto workspaceCreated = Event::bus()->m_events.workspace.created.listen([](PHLWORKSPACEREF) { markDirty(); });
    static auto workspaceRemoved = Event::bus()->m_events.workspace.removed.listen([](PHLWORKSPACEREF) { markDirty(); });
    static auto monitorFocused = Event::bus()->m_events.monitor.focused.listen([](PHLMONITOR) { markDirty(); });
    static auto monitorAdded = Event::bus()->m_events.monitor.added.listen([](PHLMONITOR) { markDirty(); });
    static auto monitorRemoved = Event::bus()->m_events.monitor.removed.listen([](PHLMONITOR) { markDirty(); });
    static auto monitorLayoutChanged = Event::bus()->m_events.monitor.layoutChanged.listen([] { markDirty(); });
    static auto configReloaded = Event::bus()->m_events.config.reloaded.listen([] { markDirty(); });
    static auto keybindsSubmap = Event::bus()->m_events.keybinds.submap.listen([](const std::string&) { markDirty(); });
    static auto renderStage = Event::bus()->m_events.render.stage.listen([](eRenderStage stage) { onRenderStage(stage); });

    watchExistingWindows();
    markDirty();

    return {"silakka54-hyprland-plugin", "Requests Silakka54 layer viewer placement refreshes after Hyprland geometry changes.", "conroy", "0.1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_windowListeners.clear();
    g_running.store(false);
    g_workerCv.notify_one();
    if (g_worker.joinable())
        g_worker.join();
}
