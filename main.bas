' ========================================================================================
' CNumericUpDown - demo harness
' ========================================================================================

#define UNICODE
#define _WIN32_WINNT &h0602

#include once "windows.bi"
#include once "AfxNova\CWindow.inc"
#include once "AfxNova\AfxStr.inc"
#include once "AfxNova\AfxGdiplus.inc"

using AfxNova


#define APPNAME          wstr("Custom Numeric UpDown")
#define APPCLASSNAME     wstr("custom_numericupdown_class")

#DEFINE GUIFONT          wstr("Segoe UI")

#DEFINE GUIFONT_9        0
#DEFINE GUIFONT_10       1
#DEFINE GUIFONTBOLD_10   2
#DEFINE MAXFONTS         3

dim shared ghFont(MAXFONTS) as HFONT

dim shared as HWND HWND_FRMMAIN

' One instance per settings row: the control is per-instance in every respect, so hovering
' or focusing one must never light up another.
#include once "frmMain.bi"
dim shared as HWND ghSpin(0 to SPIN_COUNT - 1)
dim shared as HWND ghPlainBox


type THEME_TYPE
    ForeColor             as COLORREF = BGR(190,196,206)
    ForeColorDisabled     as COLORREF = BGR( 90, 96,106)
    BackColor             as COLORREF = BGR( 33, 37, 43)
    ForeColorHot          as COLORREF = BGR(215,218,224)
    BackColorHot          as COLORREF = BGR( 44, 49, 58)
    ForeColorSelect       as COLORREF = BGR(255,255,255)
    BackColorSelect       as COLORREF = BGR( 38, 79,120)
    FocusAccent           as COLORREF = BGR( 86,156,214)
    Divider               as COLORREF = BGR( 55, 60, 69)
end type
dim shared theme as THEME_TYPE


' Include order matters, and it is the price of embedding a real editing control:
' CNumericUpDown needs CTextBox, which needs CPopupMenu, and everything paints through
' CBufferPaint. An app that already hosts CMenuBar has CPopupMenu.inc included once
' already -- it is the same file, so nothing is duplicated.
#include once "CBufferPaint.inc"
#include once "CPopupMenu.inc"
#include once "CTextBox.inc"
#include once "CNumericUpDown.inc"
#include once "frmMain.inc"


' ========================================================================================
' WinMain
' ========================================================================================
function WinMain( _
            byval hInstance     as HINSTANCE, _
            byval hPrevInstance as HINSTANCE, _
            byval szCmdLine     as zstring ptr, _
            byval nCmdShow      as long _
            ) as long


    ' Initialize the COM library
    CoInitialize(null)

    ' Initialize GDI+ (CBufferPaint draws all geometry through it). Must be running before
    ' the first WM_PAINT builds a buffer, and must outlive every one of them, so it brackets
    ' frmMain_Show.
    dim as ULONG_PTR gdipToken = AfxGdipInit()

    ' Show the main form
    function = frmMain_Show( 0 )

    ' Every window is destroyed and every CBufferPaint has run its destructor by here, so no
    ' CGp* object can still be alive. Precedes CoUninitialize: GDI+ leans on COM.
    AfxGdipShutdown( gdipToken )

    ' Uninitialize the COM library
    CoUninitialize


end function


' ========================================================================================
' Main program entry point
' ========================================================================================
end WinMain( GetModuleHandle(null), null, command(), SW_NORMAL )
