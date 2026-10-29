"""Win32 Job Object: Windows kills every child cloudflared when PyTunnel dies (even via Task Manager)."""
import ctypes
import logging
import sys
from ctypes import wintypes

logger = logging.getLogger("pytunnel.win_job")

_KILL_ON_JOB_CLOSE = 0x2000
_EXTENDED_LIMIT_INFO = 9
_PROCESS_SET_QUOTA = 0x0100
_PROCESS_TERMINATE = 0x0001


class _IoCounters(ctypes.Structure):
    _fields_ = [(name, ctypes.c_ulonglong) for name in (
        "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
        "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]


class _BasicLimit(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", ctypes.c_longlong),
        ("PerJobUserTimeLimit", ctypes.c_longlong),
        ("LimitFlags", wintypes.DWORD),
        ("MinimumWorkingSetSize", ctypes.c_size_t),
        ("MaximumWorkingSetSize", ctypes.c_size_t),
        ("ActiveProcessLimit", wintypes.DWORD),
        ("Affinity", ctypes.c_size_t),
        ("PriorityClass", wintypes.DWORD),
        ("SchedulingClass", wintypes.DWORD),
    ]


class _ExtendedLimit(ctypes.Structure):
    _fields_ = [
        ("BasicLimitInformation", _BasicLimit),
        ("IoInfo", _IoCounters),
        ("ProcessMemoryLimit", ctypes.c_size_t),
        ("JobMemoryLimit", ctypes.c_size_t),
        ("PeakProcessMemoryUsed", ctypes.c_size_t),
        ("PeakJobMemoryUsed", ctypes.c_size_t),
    ]


class JobObject:
    def __init__(self) -> None:
        self._handle = None
        if sys.platform == "win32":
            self._kernel32 = self._bind_kernel32()
            self._create()

    @property
    def active(self) -> bool:
        return bool(self._handle)

    @staticmethod
    def _bind_kernel32():
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.CreateJobObjectW.argtypes = [wintypes.LPVOID, wintypes.LPCWSTR]
        k32.CreateJobObjectW.restype = wintypes.HANDLE
        k32.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD]
        k32.SetInformationJobObject.restype = wintypes.BOOL
        k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        k32.OpenProcess.restype = wintypes.HANDLE
        k32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        k32.AssignProcessToJobObject.restype = wintypes.BOOL
        k32.CloseHandle.argtypes = [wintypes.HANDLE]
        k32.CloseHandle.restype = wintypes.BOOL
        return k32

    def _create(self) -> None:
        handle = self._kernel32.CreateJobObjectW(None, None)
        if not handle:
            logger.warning("CreateJobObject failed (error %s)", ctypes.get_last_error())
            return
        info = _ExtendedLimit()
        info.BasicLimitInformation.LimitFlags = _KILL_ON_JOB_CLOSE
        if not self._kernel32.SetInformationJobObject(handle, _EXTENDED_LIMIT_INFO, ctypes.byref(info), ctypes.sizeof(info)):
            logger.warning("SetInformationJobObject failed (error %s)", ctypes.get_last_error())
            self._kernel32.CloseHandle(handle)
            return
        self._handle = handle

    def assign(self, pid: int) -> bool:
        if not self._handle:
            return False
        process = self._kernel32.OpenProcess(_PROCESS_SET_QUOTA | _PROCESS_TERMINATE, False, pid)
        if not process:
            return False
        try:
            return bool(self._kernel32.AssignProcessToJobObject(self._handle, process))
        finally:
            self._kernel32.CloseHandle(process)


job_object = JobObject()
