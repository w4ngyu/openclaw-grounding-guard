#include "ValenBridge.h"

#include <atomic>
#include <string>
#include <thread>
#include <vector>
#include <utility>

int llama_server(int argc, char ** argv);
void llama_server_terminate();

namespace {
std::atomic<bool> active{false};
std::atomic<int> lastExit{-1};
}

extern "C" int valen_start_server(const char * model_path, const char * vision_path, bool gpu) {
    if (model_path == nullptr || *model_path == '\0') return -1;
    bool expected = false;
    if (!active.compare_exchange_strong(expected, true)) return -2;

    std::vector<std::string> args = {
        "valen-server", "-m", model_path,
        "--host", "127.0.0.1", "--port", "43227",
        "--load-mode", "mmap",
        "-c", "4096", "-b", "4096", "-ub", "4096",
        "--parallel", "1", "-t", "4", "--no-warmup"
    };

    if (vision_path != nullptr && *vision_path != '\0') {
        args.emplace_back("--mmproj");
        args.emplace_back(vision_path);
    }

    if (gpu) {
        args.emplace_back("-ngl");
        args.emplace_back("99");
    } else {
        args.emplace_back("--device");
        args.emplace_back("none");
        args.emplace_back("-ngl");
        args.emplace_back("0");
    }

    lastExit.store(-1);
    try {
        std::thread([arguments = std::move(args)]() mutable {
            int status = -3;
            try {
                std::vector<char *> argv;
                argv.reserve(arguments.size() + 1);
                for (std::string & argument : arguments) argv.push_back(argument.data());
                argv.push_back(nullptr);
                status = llama_server(static_cast<int>(arguments.size()), argv.data());
            } catch (...) {
                status = -4;
            }
            lastExit.store(status);
            active.store(false);
        }).detach();
    } catch (...) {
        active.store(false);
        lastExit.store(-5);
        return -5;
    }
    return 0;
}

extern "C" void valen_terminate_server(void) {
    if (active.load()) llama_server_terminate();
}

extern "C" int valen_server_is_running(void) {
    return active.load() ? 1 : 0;
}

extern "C" int valen_server_last_exit_code(void) {
    return lastExit.load();
}
