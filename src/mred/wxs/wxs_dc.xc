
@INCLUDE prefix.xci

#include "wx_dccan.h"
#include "wx_dcmem.h"
#include "wx_dcps.h"
#ifndef wx_mac
#include "wx_dcpan.h"
#endif
#ifdef wx_msw
#include "wx_mf.h"
#endif
#include "wx_types.h"
#ifdef wx_mac
#include "wx_dcpr.h"
#endif

@INCLUDE wxs.xci

@HEADER

@BEGINSYMBOLS solidity > ONE
@SYM "transparent" : wxTRANSPARENT
@SYM "solid" : wxSOLID
@ENDSYMBOLS

@INCLUDE wxs_drws.xci

static wxColour* dcGetTextBackground(wxDC *dc)
{
  wxColour *c = new wxColour();
  *c = dc->GetTextBackground();
  return c;
}

static wxColour* dcGetTextForeground(wxDC *dc)
{
  wxColour *c = new wxColour();
  *c = dc->GetTextForeground();
  return c;
}

@CLASSBASE wxDC "dc":"object"
@INTERFACE "dc"

@CLASSID wxTYPE_DC

@SETMARK Q = U
@INCLUDE wxs_draw.xci

// Also in wxWindow:
@ Q "get-text-extent" : void GetTextExtent(string,float*,float*,float?=NULL,float?=NULL,wxFont^=NULL,bool=FALSE); : : /CheckOk
@ Q "get-char-height" : float GetCharHeight();
@ Q "get-char-width" : float GetCharWidth();

@MACRO rZERO = return 0;
@MACRO rFALSE = return FALSE;

#ifndef wx_mac
#define HIDETHISSTATEMENT(x) x
#else
#define HIDETHISSTATEMENT(x) 
#endif

@MACRO IFNOTMAC = HIDETHISSTATEMENT(
@MACRO ENDIF = )

// @ "set-optimization" : void SetOptimization(bool); : : /IFNOTMAC/ENDIF/

#ifndef wx_mac
#define CHECKTHISONE(x) x
#else
#define CHECKTHISONE(x) 1
#endif

@MACRO CheckIcon[p] = if (!CHECKTHISONE(x<p>->Ok())) return scheme_void;

@ Q "draw-icon" : void DrawIcon(wxIcon!,float,float); : : /CheckOk|CheckIcon[0]

@ Q "blit" : bool Blit(float,float,float,float,wxCanvasDC!,float,float,SYM[logicalFunc]=wxCOPY); : : /CheckOkFalse|CheckFalse[4] : : rFALSE

@ Q "try-color" : void TryColour(wxColour!,wxColour!);

// @ Q "set-map-mode" : void SetMapMode(SYM[mapMode]); : : /CheckOk
@ Q "set-background-mode" : void SetBackgroundMode(SYM[solidity]); :  : /CheckOk
@ Q "set-user-scale" : void SetUserScale(nnfloat,nnfloat); : : /CheckOk
@ Q "set-device-origin" : void SetDeviceOrigin(float,float); : : /CheckOk

@ q "get-background" : wxBrush! GetBackground();
@ q "get-background-mode" : SYM[solidity] GetBackgroundMode();
@ q "get-brush" : wxBrush! GetBrush();
@ q "get-font" : wxFont! GetFont();
@ q "get-logical-function" : SYM[logicalFunc] GetLogicalFunction();
// @ q "get-map-mode" : SYM[mapMode] GetMapMode();
@ q "get-pen" : wxPen! GetPen();
@ m "get-text-background" : wxColour! dcGetTextBackground();
@ m "get-text-foreground" : wxColour! dcGetTextForeground();

@ q "get-size" : void GetSize(float*,float*);

// @ q "max-x" : float MaxX();
// @ q "max-y" : float MaxY();
// @ q "min-x" : float MinX();
// @ q "min-y" : float MinY();

@ q "ok?" : bool Ok();

@ Q "start-doc" : bool StartDoc(string); : : : rFALSE
@ Q "start-page" : void StartPage();
@ Q "end-doc" : void EndDoc();
@ Q "end-page" : void EndPage();

@END

@CLASSBASE wxCanvasDC "canvas-dc":"dc"

@CLASSID wxTYPE_DC_CANVAS

@CREATOR ();

@ "get-pixel" : bool GetPixel(float,float,wxColour^)

@ "begin-set-pixel" : void BeginSetPixel()
@ "end-set-pixel" : void EndSetPixel()
@ "set-pixel" : void SetPixel(float,float,wxColour^)

@END


@CLASSBASE wxMemoryDC "memory-dc":"canvas-dc"

@CLASSID wxTYPE_DC_MEMORY

@CREATOR (); <> no argument
// @CREATOR (wxCanvasDC!); <> canvas-dc%

@ "select-object" : void SelectObject(wxBitmap^);

@END

@CLASSBASE wxPostScriptDC "post-script-dc":"dc"

@CLASSID wxTYPE_DC_POSTSCRIPT

@INCLUDE wxs_dorf.xci

@CREATOR (bool=TRUE)

@END

#ifdef wx_x

class basePrinterDC : public wxObject
{
public:
  basePrinterDC()
  {
    scheme_signal_error("%s", METHODNAME("printer-dc%","initialization")": not supported for X Windows");
  }
};

#else

class basePrinterDC : public wxPrinterDC
{
public:
  basePrinterDC()
    : wxPrinterDC( )
  {
  }
};

#endif

@CLASSBASE basePrinterDC "printer-dc":"dc"

@CLASSID wxTYPE_DC_PRINTER

@CREATOR ();

@END


#ifdef wx_msw

class baseMetaFileDC : public wxMetaFileDC {
public:
  baseMetaFileDC(char *s = NULL);

  baseMetaFile* baseClose() { return (baseMetaFile *)Close(); }
};

baseMetaFileDC::baseMetaFileDC(char *s)
    : wxMetaFileDC(s)
{
}

#else

class baseMetaFileDC : public wxObject 
{
public:
  baseMetaFileDC(char * = NULL) {
    scheme_signal_error("%s", METHODNAME("meta-file-dc%","initialization")": only supported for Windows");
  }

  baseMetaFile* baseClose() { return NULL; }
};

#endif

@CLASSBASE baseMetaFileDC "meta-file-dc":"dc"

@CLASSID wxTYPE_DC_METAFILE

@CREATOR (string=NULL);

@ "close" : baseMetaFile! baseClose()

@END

