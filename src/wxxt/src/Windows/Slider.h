/*								-*- C++ -*-
 * $Id: Slider.h,v 1.2 1998/02/05 23:00:33 mflatt Exp $
 *
 * Purpose: slider panel item
 *
 * Authors: Markus Holzem and Julian Smart
 *
 * Copyright: (C) 1995, AIAI, University of Edinburgh (Julian)
 * Copyright: (C) 1995, GNU (Markus)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#ifndef Slider_h
#define Slider_h

#ifdef __GNUG__
#pragma interface
#endif

class wxPanel;

class wxSlider : public wxItem {
DECLARE_DYNAMIC_CLASS(wxSlider)
public:
    wxSlider(void);
    wxSlider(wxPanel *panel, wxFunction func, char *label,
	     int value, int min_value, int max_value, int width,
	     int x = -1, int y = -1, long style = wxHORIZONTAL, char *name = "slider");

    Bool Create(wxPanel *panel, wxFunction func, char *label,
		int value, int min_value, int max_value, int width,
		int x = -1, int y = -1, long style = wxHORIZONTAL, char *name = "slider");

    int   GetValue(void) { return value; }
    void  SetButtonColour(wxColour *col);
    void  SetValue(int value);
    void Command(wxCommandEvent &event);

    void OnSize(int width, int height);

private:
#   ifdef Have_Xt_Types
    static void EventCallback(Widget, XtPointer, XtPointer);
#   endif

    int minimum, maximum, value;
};

#endif // Slider_h
