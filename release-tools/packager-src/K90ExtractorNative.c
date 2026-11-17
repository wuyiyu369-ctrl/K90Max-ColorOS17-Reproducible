#define UNICODE
#define _UNICODE
#include <windows.h>
#include <commctrl.h>
#include <shlobj.h>
#include <shellapi.h>
#include <stdint.h>
#include <stdio.h>
#include <wchar.h>

#define IDC_PATH 101
#define IDC_BROWSE 102
#define IDC_EXTRACT 103
#define IDC_PROGRESS 104
#define IDC_STATUS 105
#define IDC_PERCENT 106
#define WM_K90_PROGRESS (WM_APP + 1)
#define WM_K90_DONE (WM_APP + 2)

static const wchar_t *kPackageFolder = L"K90Max_ColorOS17_Prague_Stage80_OneClick_20261111";
static HWND gWindow;
static HWND gPath;
static HWND gBrowse;
static HWND gExtract;
static HWND gProgress;
static HWND gStatus;
static HWND gPercent;
static HFONT gNormalFont;
static HFONT gTitleFont;
static HBITMAP gBackground;
static wchar_t gDestination[MAX_PATH * 4];
static wchar_t gError[1024];

static void SetText(HWND control, const wchar_t *text)
{
    SetWindowTextW(control, text);
}

static int IsTestMode(void)
{
    wchar_t value[8];
    return GetEnvironmentVariableW(L"K90_EXTRACT_TEST_DEST", value, 8) > 0;
}

static void BuildMarker(unsigned char marker[18])
{
    const unsigned char parts[18] = {
        'K','9','0','_','7','Z','A','_','P','A','Y','L','O','A','D','_','V','1'
    };
    int i;
    for (i = 0; i < 18; ++i) marker[i] = parts[i];
}

static int FindEmbeddedAssets(HANDLE file, uint64_t *sevenOffset, uint64_t *sevenSize,
                              uint64_t *backgroundOffset, uint64_t *backgroundSize)
{
    const DWORD limit = 16 * 1024 * 1024;
    unsigned char *buffer = (unsigned char *)HeapAlloc(GetProcessHeap(), 0, limit);
    unsigned char marker[18];
    DWORD read = 0;
    DWORD i;
    LARGE_INTEGER zero;
    int found = 0;
    if (!buffer) return 0;
    zero.QuadPart = 0;
    SetFilePointerEx(file, zero, NULL, FILE_BEGIN);
    if (!ReadFile(file, buffer, limit, &read, NULL)) {
        HeapFree(GetProcessHeap(), 0, buffer);
        return 0;
    }
    BuildMarker(marker);
    for (i = 0; i + 18 + 16 + 2 < read; ++i) {
        uint64_t sevenLength;
        uint64_t backgroundLength;
        if (memcmp(buffer + i, marker, 18) != 0) continue;
        memcpy(&sevenLength, buffer + i + 18, 8);
        memcpy(&backgroundLength, buffer + i + 26, 8);
        if (sevenLength < 100000 || sevenLength > 5 * 1024 * 1024) continue;
        if (backgroundLength < 1000 || backgroundLength > 10 * 1024 * 1024) continue;
        if (buffer[i + 34] != 'M' || buffer[i + 35] != 'Z') continue;
        *sevenOffset = (uint64_t)i + 34;
        *sevenSize = sevenLength;
        *backgroundOffset = *sevenOffset + sevenLength;
        *backgroundSize = backgroundLength;
        found = 1;
        break;
    }
    HeapFree(GetProcessHeap(), 0, buffer);
    return found;
}

static int WriteEmbeddedRange(const wchar_t *selfPath, const wchar_t *outputPath,
                              uint64_t requestedOffset, uint64_t requestedSize)
{
    HANDLE input = INVALID_HANDLE_VALUE;
    HANDLE output = INVALID_HANDLE_VALUE;
    uint64_t size = requestedSize;
    unsigned char buffer[65536];
    LARGE_INTEGER position;
    int ok = 0;

    input = CreateFileW(selfPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (input == INVALID_HANDLE_VALUE) goto cleanup;
    output = CreateFileW(outputPath, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (output == INVALID_HANDLE_VALUE) goto cleanup;
    position.QuadPart = (LONGLONG)requestedOffset;
    if (!SetFilePointerEx(input, position, NULL, FILE_BEGIN)) goto cleanup;
    while (size > 0) {
        DWORD chunk = (DWORD)(size > sizeof(buffer) ? sizeof(buffer) : size);
        DWORD got = 0;
        DWORD written = 0;
        if (!ReadFile(input, buffer, chunk, &got, NULL) || got == 0) goto cleanup;
        if (!WriteFile(output, buffer, got, &written, NULL) || written != got) goto cleanup;
        size -= got;
    }
    ok = 1;

cleanup:
    if (output != INVALID_HANDLE_VALUE) CloseHandle(output);
    if (input != INVALID_HANDLE_VALUE) CloseHandle(input);
    return ok;
}

static int GetEmbeddedAssetLayout(const wchar_t *selfPath, uint64_t *sevenOffset, uint64_t *sevenSize,
                                  uint64_t *backgroundOffset, uint64_t *backgroundSize)
{
    HANDLE input = CreateFileW(selfPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                               FILE_ATTRIBUTE_NORMAL, NULL);
    int result;
    if (input == INVALID_HANDLE_VALUE) return 0;
    result = FindEmbeddedAssets(input, sevenOffset, sevenSize, backgroundOffset, backgroundSize);
    CloseHandle(input);
    return result;
}

static int FindPercent(const char *data, DWORD length)
{
    DWORD i;
    int last = -1;
    for (i = 0; i < length; ++i) {
        if (data[i] == '%') {
            int value = 0;
            int multiplier = 1;
            int j = (int)i - 1;
            int digits = 0;
            while (j >= 0 && data[j] >= '0' && data[j] <= '9' && digits < 3) {
                value += (data[j] - '0') * multiplier;
                multiplier *= 10;
                --j;
                ++digits;
            }
            if (digits > 0 && value >= 0 && value <= 100) last = value;
        }
    }
    return last;
}

static int FileExists(const wchar_t *path)
{
    DWORD attrs = GetFileAttributesW(path);
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

static DWORD WINAPI ExtractThread(LPVOID unused)
{
    wchar_t selfPath[MAX_PATH * 4];
    wchar_t tempRoot[MAX_PATH * 4];
    wchar_t tempDir[MAX_PATH * 4];
    wchar_t sevenZip[MAX_PATH * 4];
    wchar_t command[32768];
    wchar_t launcher[MAX_PATH * 4];
    wchar_t markerFile[MAX_PATH * 4];
    wchar_t archivePath[MAX_PATH * 4];
    wchar_t overlayPath[MAX_PATH * 4];
    wchar_t selfDirectory[MAX_PATH * 4];
    wchar_t *lastSlash;
    uint64_t sevenOffset = 0;
    uint64_t sevenSize = 0;
    uint64_t backgroundOffset = 0;
    uint64_t backgroundSize = 0;
    SECURITY_ATTRIBUTES security;
    HANDLE readPipe = NULL;
    HANDLE writePipe = NULL;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    DWORD exitCode = 1;
    DWORD got;
    char output[4096];
    int success = 0;
    (void)unused;

    gError[0] = 0;
    if (!GetModuleFileNameW(NULL, selfPath, sizeof(selfPath) / sizeof(selfPath[0]))) {
        wcscpy(gError, L"无法读取自解压程序路径。");
        goto done;
    }
    wcscpy(selfDirectory, selfPath);
    lastSlash = wcsrchr(selfDirectory, L'\\');
    if (!lastSlash) {
        wcscpy(gError, L"无法确定解压程序所在目录。");
        goto done;
    }
    *lastSlash = 0;
    swprintf(archivePath, sizeof(archivePath) / sizeof(archivePath[0]),
             L"%s\\K90_PAYLOAD.7z.001", selfDirectory);
    if (!FileExists(archivePath)) {
        wcscpy(gError, L"缺少 K90_PAYLOAD.7z.001，请把 EXE 和所有分卷放在同一目录。");
        goto done;
    }
    if (!GetTempPathW(sizeof(tempRoot) / sizeof(tempRoot[0]), tempRoot)) {
        wcscpy(gError, L"无法读取系统临时目录。");
        goto done;
    }
    swprintf(tempDir, sizeof(tempDir) / sizeof(tempDir[0]), L"%sK90Extractor_%lu", tempRoot, GetCurrentProcessId());
    CreateDirectoryW(tempDir, NULL);
    swprintf(sevenZip, sizeof(sevenZip) / sizeof(sevenZip[0]), L"%s\\7za.exe", tempDir);
    if (!GetEmbeddedAssetLayout(selfPath, &sevenOffset, &sevenSize, &backgroundOffset, &backgroundSize) ||
        !WriteEmbeddedRange(selfPath, sevenZip, sevenOffset, sevenSize)) {
        wcscpy(gError, L"内置解压程序损坏或缺失。");
        goto done;
    }

    ZeroMemory(&security, sizeof(security));
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;
    if (!CreatePipe(&readPipe, &writePipe, &security, 0)) {
        wcscpy(gError, L"无法创建解压进度管道。");
        goto done;
    }
    SetHandleInformation(readPipe, HANDLE_FLAG_INHERIT, 0);

    ZeroMemory(&startup, sizeof(startup));
    ZeroMemory(&process, sizeof(process));
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    startup.hStdOutput = writePipe;
    startup.hStdError = writePipe;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    swprintf(command, sizeof(command) / sizeof(command[0]),
             L"\"%s\" x -y -aoa -bsp1 -bso1 -bse1 -o\"%s\" \"%s\"",
             sevenZip, gDestination, archivePath);
    if (!CreateProcessW(NULL, command, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, tempDir, &startup, &process)) {
        wcscpy(gError, L"无法启动内置 7-Zip。");
        goto done;
    }
    CloseHandle(writePipe);
    writePipe = NULL;

    while (ReadFile(readPipe, output, sizeof(output), &got, NULL) && got > 0) {
        int value = FindPercent(output, got);
        if (value >= 0) PostMessageW(gWindow, WM_K90_PROGRESS, (WPARAM)value, 0);
    }
    WaitForSingleObject(process.hProcess, INFINITE);
    GetExitCodeProcess(process.hProcess, &exitCode);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    if (exitCode != 0) {
        swprintf(gError, sizeof(gError) / sizeof(gError[0]), L"7-Zip 解压失败，退出码：%lu", exitCode);
        goto done;
    }

    swprintf(overlayPath, sizeof(overlayPath) / sizeof(overlayPath[0]),
             L"%s\\K90_UPDATE.7z", selfDirectory);
    if (FileExists(overlayPath)) {
        ZeroMemory(&startup, sizeof(startup));
        ZeroMemory(&process, sizeof(process));
        startup.cb = sizeof(startup);
        startup.dwFlags = STARTF_USESHOWWINDOW;
        startup.wShowWindow = SW_HIDE;
        swprintf(command, sizeof(command) / sizeof(command[0]),
                 L"\"%s\" x -t7z -y -aoa -o\"%s\" \"%s\"",
                 sevenZip, gDestination, overlayPath);
        if (!CreateProcessW(NULL, command, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                            NULL, tempDir, &startup, &process)) {
            wcscpy(gError, L"无法应用刷机脚本更新层。");
            goto done;
        }
        WaitForSingleObject(process.hProcess, INFINITE);
        GetExitCodeProcess(process.hProcess, &exitCode);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        if (exitCode != 0) {
            swprintf(gError, sizeof(gError) / sizeof(gError[0]),
                     L"刷机脚本更新层应用失败，退出码：%lu", exitCode);
            goto done;
        }
    }

    swprintf(launcher, sizeof(launcher) / sizeof(launcher[0]), L"%s\\%s\\START_FLASH.cmd", gDestination, kPackageFolder);
    if (!FileExists(launcher)) {
        wcscpy(gError, L"解压后没有找到 START_FLASH.cmd。");
        goto done;
    }

    if (IsTestMode()) {
        swprintf(markerFile, sizeof(markerFile) / sizeof(markerFile[0]), L"%s\\K90_EXTRACT_TEST_OK.txt", gDestination);
        {
            HANDLE marker = CreateFileW(markerFile, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
            if (marker != INVALID_HANDLE_VALUE) {
                DWORD written;
                WriteFile(marker, "OK", 2, &written, NULL);
                CloseHandle(marker);
            }
        }
    } else {
        ShellExecuteW(NULL, L"open", launcher, NULL, gDestination, SW_SHOWNORMAL);
    }
    success = 1;

done:
    if (writePipe) CloseHandle(writePipe);
    if (readPipe) CloseHandle(readPipe);
    DeleteFileW(sevenZip);
    RemoveDirectoryW(tempDir);
    PostMessageW(gWindow, WM_K90_DONE, (WPARAM)success, 0);
    return 0;
}

static int CALLBACK BrowseCallback(HWND window, UINT message, LPARAM data, LPARAM initial)
{
    (void)data;
    if (message == BFFM_INITIALIZED && initial)
        SendMessageW(window, BFFM_SETSELECTIONW, TRUE, initial);
    return 0;
}

static void BrowseForFolder(HWND owner)
{
    BROWSEINFOW info;
    PIDLIST_ABSOLUTE item;
    wchar_t selected[MAX_PATH * 4];
    wchar_t current[MAX_PATH * 4];
    GetWindowTextW(gPath, current, sizeof(current) / sizeof(current[0]));
    ZeroMemory(&info, sizeof(info));
    info.hwndOwner = owner;
    info.lpszTitle = L"请选择刷机包解压到哪个目录";
    info.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
    info.lpfn = BrowseCallback;
    info.lParam = (LPARAM)current;
    item = SHBrowseForFolderW(&info);
    if (item) {
        if (SHGetPathFromIDListW(item, selected)) SetText(gPath, selected);
        CoTaskMemFree(item);
    }
}

static void StartExtraction(HWND owner)
{
    ULARGE_INTEGER freeBytes;
    wchar_t root[MAX_PATH * 4];
    wchar_t testDestination[MAX_PATH * 4];
    wchar_t *slash;
    GetWindowTextW(gPath, gDestination, sizeof(gDestination) / sizeof(gDestination[0]));
    if (!gDestination[0]) {
        MessageBoxW(owner, L"请先选择解压目录。", L"提示", MB_OK | MB_ICONWARNING);
        return;
    }
    CreateDirectoryW(gDestination, NULL);
    wcscpy(root, gDestination);
    slash = wcschr(root, L'\\');
    if (slash) slash[1] = 0;
    if (!IsTestMode() && GetDiskFreeSpaceExW(root, &freeBytes, NULL, NULL) &&
        freeBytes.QuadPart < 16ULL * 1024ULL * 1024ULL * 1024ULL) {
        if (MessageBoxW(owner,
                        L"目标磁盘可用空间低于 16 GB，可能无法完成解压。仍要继续吗？",
                        L"空间不足", MB_YESNO | MB_ICONWARNING) != IDYES)
            return;
    }
    EnableWindow(gPath, FALSE);
    EnableWindow(gBrowse, FALSE);
    EnableWindow(gExtract, FALSE);
    SetText(gStatus, L"正在准备内置解压程序……");
    SendMessageW(gProgress, PBM_SETPOS, 0, 0);
    SetText(gPercent, L"0%");
    if (!CreateThread(NULL, 0, ExtractThread, NULL, 0, NULL)) {
        MessageBoxW(owner, L"无法启动解压线程。", L"错误", MB_OK | MB_ICONERROR);
        EnableWindow(gPath, TRUE);
        EnableWindow(gBrowse, TRUE);
        EnableWindow(gExtract, TRUE);
    }
    (void)testDestination;
}

static void CreateLabel(HWND parent, const wchar_t *text, int x, int y, int width, int height, HFONT font, COLORREF color)
{
    HWND label = CreateWindowExW(0, L"STATIC", text, WS_CHILD | WS_VISIBLE | SS_LEFT,
                                 x, y, width, height, parent, NULL, GetModuleHandleW(NULL), NULL);
    SendMessageW(label, WM_SETFONT, (WPARAM)font, TRUE);
    SetPropW(label, L"K90Color", (HANDLE)(uintptr_t)color);
}

static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message) {
    case WM_CREATE:
    {
        wchar_t desktop[MAX_PATH * 4];
        gNormalFont = CreateFontW(-18, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                  OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                  DEFAULT_PITCH, L"Microsoft YaHei UI");
        gTitleFont = CreateFontW(-38, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                 OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                 DEFAULT_PITCH, L"Microsoft YaHei UI");
        CreateLabel(window, L"请选择解压目录。需要至少 16 GB 可用空间，解压完成后自动打开中文刷机向导。",
                    56, 528, 780, 30, gNormalFont, RGB(220, 226, 234));
        SHGetFolderPathW(NULL, CSIDL_DESKTOPDIRECTORY, NULL, SHGFP_TYPE_CURRENT, desktop);
        gPath = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", desktop, WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                56, 558, 650, 32, window, (HMENU)IDC_PATH, GetModuleHandleW(NULL), NULL);
        SendMessageW(gPath, WM_SETFONT, (WPARAM)gNormalFont, TRUE);
        gBrowse = CreateWindowExW(0, L"BUTTON", L"选择目录", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                  722, 557, 120, 34, window, (HMENU)IDC_BROWSE, GetModuleHandleW(NULL), NULL);
        SendMessageW(gBrowse, WM_SETFONT, (WPARAM)gNormalFont, TRUE);
        gProgress = CreateWindowExW(0, PROGRESS_CLASSW, NULL, WS_CHILD | WS_VISIBLE,
                                    56, 608, 650, 24, window, (HMENU)IDC_PROGRESS, GetModuleHandleW(NULL), NULL);
        SendMessageW(gProgress, PBM_SETRANGE, 0, MAKELPARAM(0, 100));
        gPercent = CreateWindowExW(0, L"STATIC", L"0%", WS_CHILD | WS_VISIBLE | SS_LEFT,
                                   722, 606, 90, 28, window, (HMENU)IDC_PERCENT, GetModuleHandleW(NULL), NULL);
        SendMessageW(gPercent, WM_SETFONT, (WPARAM)gNormalFont, TRUE);
        SetPropW(gPercent, L"K90Color", (HANDLE)(uintptr_t)RGB(245, 249, 251));
        gStatus = CreateWindowExW(0, L"STATIC", L"等待开始", WS_CHILD | WS_VISIBLE | SS_LEFT,
                                  56, 643, 590, 42, window, (HMENU)IDC_STATUS, GetModuleHandleW(NULL), NULL);
        SendMessageW(gStatus, WM_SETFONT, (WPARAM)gNormalFont, TRUE);
        SetPropW(gStatus, L"K90Color", (HANDLE)(uintptr_t)RGB(185, 194, 207));
        gExtract = CreateWindowExW(0, L"BUTTON", L"开始解压", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
                                   680, 652, 162, 48, window, (HMENU)IDC_EXTRACT, GetModuleHandleW(NULL), NULL);
        SendMessageW(gExtract, WM_SETFONT, (WPARAM)gNormalFont, TRUE);
        ShowWindow(gExtract, SW_SHOW);
        BringWindowToTop(gExtract);
        if (GetEnvironmentVariableW(L"K90_EXTRACT_TEST_DEST", desktop, sizeof(desktop) / sizeof(desktop[0])) > 0) {
            SetText(gPath, desktop);
            PostMessageW(window, WM_COMMAND, MAKEWPARAM(IDC_EXTRACT, BN_CLICKED), (LPARAM)gExtract);
        }
        return 0;
    }
    case WM_COMMAND:
        if (LOWORD(wParam) == IDC_BROWSE) BrowseForFolder(window);
        else if (LOWORD(wParam) == IDC_EXTRACT) StartExtraction(window);
        return 0;
    case WM_K90_PROGRESS:
    {
        wchar_t value[16];
        int percent = (int)wParam;
        SendMessageW(gProgress, PBM_SETPOS, percent, 0);
        swprintf(value, sizeof(value) / sizeof(value[0]), L"%d%%", percent);
        SetText(gPercent, value);
        SetText(gStatus, L"正在解压刷机包，请稍候……");
        return 0;
    }
    case WM_K90_DONE:
        if (wParam) {
            SendMessageW(gProgress, PBM_SETPOS, 100, 0);
            SetText(gPercent, L"100%");
            SetText(gStatus, L"解压完成，正在打开中文刷机向导……");
            if (IsTestMode()) PostQuitMessage(0);
            else DestroyWindow(window);
        } else if (IsTestMode()) {
            wchar_t errorFile[MAX_PATH * 4];
            HANDLE file;
            DWORD written;
            swprintf(errorFile, sizeof(errorFile) / sizeof(errorFile[0]), L"%s\\K90_EXTRACT_TEST_ERROR.txt", gDestination);
            file = CreateFileW(errorFile, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
            if (file != INVALID_HANDLE_VALUE) {
                WriteFile(file, gError, (DWORD)(wcslen(gError) * sizeof(wchar_t)), &written, NULL);
                CloseHandle(file);
            }
            PostQuitMessage(3);
        } else {
            SetText(gStatus, gError);
            MessageBoxW(window, gError, L"解压失败", MB_OK | MB_ICONERROR);
            EnableWindow(gPath, TRUE);
            EnableWindow(gBrowse, TRUE);
            EnableWindow(gExtract, TRUE);
        }
        return 0;
    case WM_CTLCOLORSTATIC:
    {
        HDC dc = (HDC)wParam;
        HWND child = (HWND)lParam;
        HANDLE color = GetPropW(child, L"K90Color");
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, color ? (COLORREF)(uintptr_t)color : RGB(245, 249, 251));
        return (LRESULT)GetStockObject(NULL_BRUSH);
    }
    case WM_PAINT:
    {
        PAINTSTRUCT paint;
        RECT rect;
        HDC dc = BeginPaint(window, &paint);
        int y;
        GetClientRect(window, &rect);
        for (y = 0; y < rect.bottom; ++y) {
            int r = 10 + (9 * y / (rect.bottom ? rect.bottom : 1));
            int g = 15 + (37 * y / (rect.bottom ? rect.bottom : 1));
            int b = 23 + (26 * y / (rect.bottom ? rect.bottom : 1));
            HPEN pen = CreatePen(PS_SOLID, 1, RGB(r, g, b));
            HPEN old = (HPEN)SelectObject(dc, pen);
            MoveToEx(dc, 0, y, NULL);
            LineTo(dc, rect.right, y);
            SelectObject(dc, old);
            DeleteObject(pen);
        }
        if (gBackground) {
            HDC memory = CreateCompatibleDC(dc);
            HBITMAP oldBitmap = (HBITMAP)SelectObject(memory, gBackground);
            BITMAP bitmap;
            GetObject(gBackground, sizeof(bitmap), &bitmap);
            SetStretchBltMode(dc, HALFTONE);
            StretchBlt(dc, 0, 0, rect.right, 520, memory, 0, 0,
                       bitmap.bmWidth, bitmap.bmHeight, SRCCOPY);
            SelectObject(memory, oldBitmap);
            DeleteDC(memory);
        }
        EndPaint(window, &paint);
        return 0;
    }
    case WM_DESTROY:
        if (gNormalFont) DeleteObject(gNormalFont);
        if (gTitleFont) DeleteObject(gTitleFont);
        if (gBackground) DeleteObject(gBackground);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR commandLine, int show)
{
    WNDCLASSEXW windowClass;
    MSG message;
    INITCOMMONCONTROLSEX controls;
    wchar_t selfPath[MAX_PATH * 4];
    wchar_t tempRoot[MAX_PATH * 4];
    wchar_t backgroundPath[MAX_PATH * 4];
    uint64_t sevenOffset = 0;
    uint64_t sevenSize = 0;
    uint64_t backgroundOffset = 0;
    uint64_t backgroundSize = 0;
    (void)previous;
    (void)commandLine;
    (void)show;
    controls.dwSize = sizeof(controls);
    controls.dwICC = ICC_PROGRESS_CLASS;
    InitCommonControlsEx(&controls);
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (GetModuleFileNameW(NULL, selfPath, sizeof(selfPath) / sizeof(selfPath[0])) &&
        GetTempPathW(sizeof(tempRoot) / sizeof(tempRoot[0]), tempRoot) &&
        GetEmbeddedAssetLayout(selfPath, &sevenOffset, &sevenSize, &backgroundOffset, &backgroundSize)) {
        swprintf(backgroundPath, sizeof(backgroundPath) / sizeof(backgroundPath[0]),
                 L"%sK90Background_%lu.bmp", tempRoot, GetCurrentProcessId());
        if (WriteEmbeddedRange(selfPath, backgroundPath, backgroundOffset, backgroundSize)) {
            gBackground = (HBITMAP)LoadImageW(NULL, backgroundPath, IMAGE_BITMAP, 0, 0,
                                              LR_LOADFROMFILE | LR_CREATEDIBSECTION);
            DeleteFileW(backgroundPath);
        }
    }
    ZeroMemory(&windowClass, sizeof(windowClass));
    windowClass.cbSize = sizeof(windowClass);
    windowClass.hInstance = instance;
    windowClass.lpfnWndProc = WindowProc;
    windowClass.lpszClassName = L"K90ExtractorWindow";
    windowClass.hCursor = LoadCursorW(NULL, IDC_ARROW);
    windowClass.hIcon = LoadIconW(NULL, IDI_APPLICATION);
    windowClass.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    if (!RegisterClassExW(&windowClass)) return 1;
    gWindow = CreateWindowExW(0, windowClass.lpszClassName,
                              L"K90 Max ColorOS 17 一键刷机包",
                              WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                              CW_USEDEFAULT, CW_USEDEFAULT, 916, 760,
                              NULL, NULL, instance, NULL);
    if (!gWindow) return 2;
    ShowWindow(gWindow, SW_SHOW);
    UpdateWindow(gWindow);
    while (GetMessageW(&message, NULL, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    CoUninitialize();
    return 0;
}
