'    PsNumericUpDown - reusable owner-drawn numeric up/down control
'    Copyright (C) 2016-2026 Paul Squires, PlanetSquires Software
'
'    This program is free software: you can redistribute it and/or modify
'    it under the terms of the GNU General Public License as published by
'    the Free Software Foundation, either version 3 of the License, or
'    (at your option) any later version.
'
'    This program is distributed in the hope that it will be useful,
'    but WITHOUT any WARRANTY; without even the implied warranty of
'    MERCHANTABILITY or FITNESS for A PARTICULAR PURPOSE.  See the
'    GNU General Public License for more details.

#pragma once

' The demo lays the spinners out as a settings pane: one per row, label on the left, the
' control on the right -- the arrangement it was drawn for.
#define SPIN_COUNT   6

#define IDC_FRMMAIN_SPIN_FIRST   1000
#define IDC_FRMMAIN_SPIN_TEST    1098   ' the throwaway control the self-test measures
#define IDC_FRMMAIN_TEXTBOX      1099   ' a plain PsTextBox, to prove Tab walks the nesting

declare function frmMain_Show( byval hWndParent as HWND ) as LRESULT
