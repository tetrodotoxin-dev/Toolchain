// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/process/child.hpp"

#include <errno.h>
#include <stdlib.h>

#include "toolchain/validation/clock.hpp"
#include "toolchain/validation/stream.hpp"
#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#endif
using namespace Toolchain::Validation;

static constexpr size_t max_arguments = 32;

// A Request already contains the complete input transaction. Temporary streams
// let the child consume it and emit arbitrary output without pipe backpressure
// or a second asynchronous I/O engine in the validation harness.
struct Streams {
  FILE* input = temporary_stream();
  FILE* output = temporary_stream();
  FILE* error = temporary_stream();

  ~Streams() {
    if (input) {
      fclose(input);
    }
    if (output) {
      fclose(output);
    }
    if (error) {
      fclose(error);
    }
  }
};

Process::Observation::Observation(Observation&& other) noexcept
    : launched(other.launched),
      timed_out(other.timed_out),
      exit_status(other.exit_status),
      standard_input(other.standard_input),
      standard_output(other.standard_output),
      standard_error(other.standard_error),
      runner_error(other.runner_error) {
  other.standard_input = {};
  other.standard_output = {};
  other.standard_error = {};
}
Process::Observation::~Observation() {
  free(const_cast<void*>(standard_input.data));
  free(const_cast<void*>(standard_output.data));
  free(const_cast<void*>(standard_error.data));
}
static auto capture(FILE* stream, Bytes& bytes) -> bool {
  if (fseek(stream, 0, SEEK_SET)) {
    return false;
  }
  unsigned char block[4096];
  size_t capacity = 0;
  while (const auto size = fread(block, 1, sizeof(block), stream)) {
    if (bytes.size > SIZE_MAX - size) {
      return false;
    }
    const size_t required = bytes.size + size;
    if (required > capacity) {
      capacity = required <= SIZE_MAX / 2 ? required * 2 : required;
      void* allocation = realloc(const_cast<void*>(bytes.data), capacity);
      if (!allocation) {
        return false;
      }
      bytes.data = allocation;
    }
    memcpy(
        static_cast<unsigned char*>(const_cast<void*>(bytes.data)) + bytes.size,
        block, size);
    bytes.size += size;
  }
  return !ferror(stream);
}
static auto valid_argument(Bytes value) -> bool {
  return !value.size || (value.data && !memchr(value.data, 0, value.size));
}

#ifdef _WIN32
// CreateProcess accepts one command line. Quote each argument according to the
// Microsoft CRT rules, including empty strings and trailing backslashes.
static auto append_argument(char* output, Bytes value) -> char* {
  *output++ = '"';
  size_t slashes = 0;
  for (size_t i = 0; i < value.size; ++i) {
    const char byte = static_cast<const char*>(value.data)[i];
    if (byte == '\\') {
      ++slashes;
      continue;
    }
    const size_t escaped = byte == '"' ? slashes * 2 + 1 : slashes;
    memset(output, '\\', escaped);
    output += escaped;
    *output++ = byte;
    slashes = 0;
  }
  memset(output, '\\', slashes * 2);
  output += slashes * 2;
  *output++ = '"';
  *output++ = ' ';
  return output;
}
static auto execute(
    const Process::Request& request,
    Streams& streams,
    Process::Observation& observation) -> void {
  // Quoting can double every byte. Bound the UTF8 scratch buffer before
  // writing it, then let Windows check the actual UTF16 command limit.
  size_t text_size = request.executable.size;
  for (size_t i = 0; i < request.argument_count; ++i) {
    if (request.arguments[i].size > 32767 ||
        text_size > 32767 - request.arguments[i].size) {
      observation.runner_error = "Windows command line too long";
      return;
    }
    text_size += request.arguments[i].size;
  }
  if (text_size > 32767) {
    observation.runner_error = "Windows command line too long";
    return;
  }
  char command[65536 + (max_arguments + 1) * 2];
  char* end = append_argument(command, request.executable);
  for (size_t i = 0; i < request.argument_count; ++i) {
    end = append_argument(end, request.arguments[i]);
  }
  *end = 0;
  wchar_t wide[32768];
  if (!MultiByteToWideChar(
          CP_UTF8, MB_ERR_INVALID_CHARS, command, -1, wide, 32768)) {
    observation.runner_error = "invalid Windows command line";
    return;
  }

  HANDLE handles[] = {
    reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(streams.input))),
    reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(streams.output))),
    reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(streams.error))),
  };
  for (HANDLE handle : handles) {
    if (!SetHandleInformation(
            handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)) {
      observation.runner_error = "stream inheritance failed";
      return;
    }
  }

  // Limit inheritance to the three streams instead of lending unrelated host
  // handles to a fixture. Storage belongs to this synchronous launch.
  SIZE_T size = 0;
  InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
  void* attributes = malloc(size);
  if (!attributes) {
    observation.runner_error = "process attributes allocation failed";
    return;
  }
  STARTUPINFOEXW startup = {};
  startup.StartupInfo.cb = sizeof(startup);
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.StartupInfo.hStdInput = handles[0];
  startup.StartupInfo.hStdOutput = handles[1];
  startup.StartupInfo.hStdError = handles[2];
  startup.lpAttributeList =
      reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attributes);
  if (!InitializeProcThreadAttributeList(
          startup.lpAttributeList, 1, 0, &size)) {
    free(attributes);
    observation.runner_error = "process attributes failed";
    return;
  }
  PROCESS_INFORMATION process = {};
  const bool ready = UpdateProcThreadAttribute(
      startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, handles,
      sizeof(handles), nullptr, nullptr);
  const bool launched =
      ready && CreateProcessW(
                   nullptr, wide, nullptr, nullptr, TRUE,
                   EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW, nullptr,
                   nullptr, &startup.StartupInfo, &process);
  DeleteProcThreadAttributeList(startup.lpAttributeList);
  free(attributes);
  if (!launched) {
    observation.runner_error = "child launch failed";
    return;
  }

  observation.launched = true;
  CloseHandle(process.hThread);
  const uint64_t milliseconds = request.timeout_nanoseconds / 1'000'000 +
                                (request.timeout_nanoseconds % 1'000'000 != 0);
  const DWORD timeout =
      DWORD(milliseconds < INFINITE ? milliseconds : INFINITE - 1);
  const DWORD waited = WaitForSingleObject(process.hProcess, timeout);
  if (waited != WAIT_OBJECT_0) {
    observation.timed_out = waited == WAIT_TIMEOUT;
    if (waited != WAIT_TIMEOUT) {
      observation.runner_error = "child wait failed";
    }
    TerminateProcess(process.hProcess, 137);
    WaitForSingleObject(process.hProcess, INFINITE);
  }
  DWORD status = 0;
  if (!GetExitCodeProcess(process.hProcess, &status)) {
    observation.runner_error = "child status failed";
  }
  observation.exit_status = int32_t(status);
  CloseHandle(process.hProcess);
}
#else
static auto execute(
    const Process::Request& request,
    Streams& streams,
    Process::Observation& observation) -> void {
  char* arguments[max_arguments + 2] = {};
  for (size_t i = 0; i <= request.argument_count; ++i) {
    const Bytes value = i ? request.arguments[i - 1] : request.executable;
    arguments[i] = static_cast<char*>(malloc(value.size + 1));
    if (!arguments[i]) {
      for (size_t j = 0; j < i; ++j) {
        free(arguments[j]);
      }
      observation.runner_error = "argument allocation failed";
      return;
    }
    if (value.size) {
      memcpy(arguments[i], value.data, value.size);
    }
    arguments[i][value.size] = 0;
  }

  pid_t child = fork();
  if (child != 0) {
    for (size_t i = 0; i <= request.argument_count; ++i) {
      free(arguments[i]);
    }
  }
  if (child < 0) {
    observation.runner_error = "fork failed";
    return;
  }
  if (!child) {
    if (dup2(fileno(streams.input), STDIN_FILENO) < 0 ||
        dup2(fileno(streams.output), STDOUT_FILENO) < 0 ||
        dup2(fileno(streams.error), STDERR_FILENO) < 0) {
      _exit(126);
    }
    fclose(streams.input);
    fclose(streams.output);
    fclose(streams.error);
    execv(arguments[0], arguments);
    _exit(127);
  }

  observation.launched = true;
  const auto started = time_ns();
  int status = 0;
  for (;;) {
    const pid_t waited = waitpid(child, &status, WNOHANG);
    if (waited == child) {
      break;
    }
    if (waited < 0 && errno != EINTR) {
      observation.runner_error = "child wait failed";
      break;
    }
    if ((time_ns() - started) >= request.timeout_nanoseconds) {
      observation.timed_out = true;
      kill(child, SIGKILL);
      while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
      }
      break;
    }
    const timespec delay = {0, 1'000'000};
    nanosleep(&delay, nullptr);
  }
  if (WIFEXITED(status)) {
    observation.exit_status = WEXITSTATUS(status);
  } else if (WIFSIGNALED(status)) {
    observation.exit_status = 128 + WTERMSIG(status);
  }
}
#endif

auto Process::run(const Request& request) -> Observation {
  Observation observation;
  if (!request.executable.size || !valid_argument(request.executable) ||
      request.argument_count > max_arguments ||
      (request.argument_count && !request.arguments) ||
      (request.standard_input.size && !request.standard_input.data)) {
    observation.runner_error = "invalid child arguments";
    return observation;
  }
  for (size_t i = 0; i < request.argument_count; ++i) {
    if (!valid_argument(request.arguments[i])) {
      observation.runner_error = "invalid child arguments";
      return observation;
    }
  }

  Streams streams;
  if (!streams.input || !streams.output || !streams.error ||
      fwrite(
          request.standard_input.data, 1, request.standard_input.size,
          streams.input) != request.standard_input.size ||
      fflush(streams.input) || fseek(streams.input, 0, SEEK_SET)) {
    observation.runner_error = "stream setup failed";
    return observation;
  }

  void* input = request.standard_input.size
                    ? malloc(request.standard_input.size)
                    : nullptr;
  if (request.standard_input.size && !input) {
    observation.runner_error = "input allocation failed";
    return observation;
  }
  if (input) {
    memcpy(input, request.standard_input.data, request.standard_input.size);
  }
  observation.standard_input = {input, request.standard_input.size};
  execute(request, streams, observation);
  const bool output = capture(streams.output, observation.standard_output);
  const bool error = capture(streams.error, observation.standard_error);
  if (!output || !error) {
    observation.runner_error = "stream capture failed";
  }
  return observation;
}

auto Process::compare(
    const Observation& observation,
    const Expectation& expectation) -> Difference {
  if (!observation.launched || observation.runner_error != nullptr) {
    return Difference::Launch;
  }

  if ((observation.standard_input.size != expectation.standard_input.size ||
       (observation.standard_input.size &&
        memcmp(
            observation.standard_input.data, expectation.standard_input.data,
            observation.standard_input.size)))) {
    return Difference::StandardInput;
  }

  if (observation.timed_out != expectation.timed_out) {
    return Difference::Timeout;
  }

  if ((observation.standard_output.size != expectation.standard_output.size ||
       (observation.standard_output.size &&
        memcmp(
            observation.standard_output.data, expectation.standard_output.data,
            observation.standard_output.size)))) {
    return Difference::StandardOutput;
  }

  if ((observation.standard_error.size != expectation.standard_error.size ||
       (observation.standard_error.size &&
        memcmp(
            observation.standard_error.data, expectation.standard_error.data,
            observation.standard_error.size)))) {
    return Difference::StandardError;
  }

  if (observation.exit_status != expectation.exit_status) {
    return Difference::ExitStatus;
  }

  return Difference::None;
}
