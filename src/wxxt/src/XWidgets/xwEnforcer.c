/* Generated by wbuild
 * (generator version 3.2)
 */
#include <X11/IntrinsicP.h>
#include <X11/StringDefs.h>
#include <stdio.h>
#include "xwTabString.h"
#include <./xwEnforcerP.h>
static void propagateKey(
#if NeedFunctionPrototypes
Widget,XEvent*,String*,Cardinal*
#endif
);

static XtActionsRec actionsList[] = {
{"propagateKey", propagateKey},
};
static void _resolve_inheritance(
#if NeedFunctionPrototypes
WidgetClass
#endif
);
static void initialize(
#if NeedFunctionPrototypes
Widget ,Widget,ArgList ,Cardinal *
#endif
);
static void destroy(
#if NeedFunctionPrototypes
Widget
#endif
);
static Boolean  set_values(
#if NeedFunctionPrototypes
Widget ,Widget ,Widget,ArgList ,Cardinal *
#endif
);
static void _expose(
#if NeedFunctionPrototypes
Widget,XEvent *,Region 
#endif
);
static void resize(
#if NeedFunctionPrototypes
Widget
#endif
);
static void insert_child(
#if NeedFunctionPrototypes
Widget 
#endif
);
static void change_managed(
#if NeedFunctionPrototypes
Widget
#endif
);
static XtGeometryResult  geometry_manager(
#if NeedFunctionPrototypes
Widget ,XtWidgetGeometry *,XtWidgetGeometry *
#endif
);
static void compute_inside(
#if NeedFunctionPrototypes
Widget,Position *,Position *,int *,int *
#endif
);
static void highlight_border(
#if NeedFunctionPrototypes
Widget
#endif
);
static void unhighlight_border(
#if NeedFunctionPrototypes
Widget
#endif
);
static char  propagateTranslation[] = "<KeyPress> : propagateKey() \n <KeyRelease> : propagateKey()";;
static XtTranslations  propagate_trans = NULL ;;
static void compute_label_size(
#if NeedFunctionPrototypes
Widget
#endif
);
static void make_textgc(
#if NeedFunctionPrototypes
Widget
#endif
);
static void make_graygc(
#if NeedFunctionPrototypes
Widget
#endif
);
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void compute_label_size(Widget self)
#else
static void compute_label_size(self)Widget self;
#endif
{
    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.label) {
	int len = strlen(((XfwfEnforcerWidget)self)->xfwfEnforcer.label);
	((XfwfEnforcerWidget)self)->xfwfEnforcer.labelWidth  = XfwfTextWidth(XtDisplay(self), ((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont, ((XfwfEnforcerWidget)self)->xfwfEnforcer.label, len, NULL);
	((XfwfEnforcerWidget)self)->xfwfEnforcer.labelHeight = (wx_ASCENT(((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((wxExtFont)((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont))
			+ wx_DESCENT(((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((wxExtFont)((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont)));
    } else {
	((XfwfEnforcerWidget)self)->xfwfEnforcer.labelWidth = ((XfwfEnforcerWidget)self)->xfwfEnforcer.labelHeight = 0;
    }
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void make_textgc(Widget self)
#else
static void make_textgc(self)Widget self;
#endif
{
    XtGCMask mask;
    XGCValues values;

    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc != NULL) XtReleaseGC(self, ((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc);
    values.background = ((XfwfEnforcerWidget)self)->core.background_pixel;
    mask = GCBackground | GCForeground;
    if (!((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont) {
      values.foreground = ((XfwfEnforcerWidget)self)->xfwfEnforcer.foreground;
      values.font = ((XfwfEnforcerWidget)self)->xfwfEnforcer.font->fid;
      mask |= GCFont;
    } else 
      values.foreground = values.background;
    ((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc = XtGetGC(self, mask, &values);
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void make_graygc(Widget self)
#else
static void make_graygc(self)Widget self;
#endif
{
    XtGCMask mask;
    XGCValues values;

    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc != NULL) XtReleaseGC(self, ((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc);

   if (!wx_enough_colors(XtScreen(self))) {
      /* A GC to draw over text: */
      values.foreground = ((XfwfEnforcerWidget)self)->core.background_pixel;
      values.stipple = GetGray(self);
      values.fill_style = FillStippled;
      mask = GCForeground | GCStipple | GCFillStyle;
    } else {
      /* A GC for drawing gray text: */
      static Pixel color;
      values.background = ((XfwfEnforcerWidget)self)->core.background_pixel;
      ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.darker_color(self, ((XfwfEnforcerWidget)self)->core.background_pixel, &color);
      values.foreground = color;
      mask = GCBackground | GCForeground;
      if (((XfwfEnforcerWidget)self)->xfwfEnforcer.font) {
	values.font = ((XfwfEnforcerWidget)self)->xfwfEnforcer.font->fid;
	mask |= GCFont;
      }
    }
 
    ((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc = XtGetGC(self, mask, &values);
}

static XtResource resources[] = {
{XtNshrinkToFit,XtCShrinkToFit,XtRBoolean,sizeof(((XfwfEnforcerRec*)NULL)->xfwfEnforcer.shrinkToFit),XtOffsetOf(XfwfEnforcerRec,xfwfEnforcer.shrinkToFit),XtRImmediate,(XtPointer)FALSE },
{XtNrel_width,XtCRel_width,XtRFloat,sizeof(((XfwfEnforcerRec*)NULL)->xfwfBoard.rel_width),XtOffsetOf(XfwfEnforcerRec,xfwfBoard.rel_width),XtRString,(XtPointer)"0.0"},
{XtNrel_height,XtCRel_height,XtRFloat,sizeof(((XfwfEnforcerRec*)NULL)->xfwfBoard.rel_height),XtOffsetOf(XfwfEnforcerRec,xfwfBoard.rel_height),XtRString,(XtPointer)"0.0"},
{XtNabs_width,XtCAbs_width,XtRPosition,sizeof(((XfwfEnforcerRec*)NULL)->xfwfBoard.abs_width),XtOffsetOf(XfwfEnforcerRec,xfwfBoard.abs_width),XtRImmediate,(XtPointer)10 },
{XtNabs_height,XtCAbs_height,XtRPosition,sizeof(((XfwfEnforcerRec*)NULL)->xfwfBoard.abs_height),XtOffsetOf(XfwfEnforcerRec,xfwfBoard.abs_height),XtRImmediate,(XtPointer)10 },
{XtNlabel,XtCLabel,XtRString,sizeof(((XfwfEnforcerRec*)NULL)->xfwfEnforcer.label),XtOffsetOf(XfwfEnforcerRec,xfwfEnforcer.label),XtRImmediate,(XtPointer)NULL },
{XtNfont,XtCFont,XtRFontStruct,sizeof(((XfwfEnforcerRec*)NULL)->xfwfEnforcer.font),XtOffsetOf(XfwfEnforcerRec,xfwfEnforcer.font),XtRString,(XtPointer)XtDefaultFont },
{XtNxfont,XtCXFont,XtRvoid,sizeof(((XfwfEnforcerRec*)NULL)->xfwfEnforcer.xfont),XtOffsetOf(XfwfEnforcerRec,xfwfEnforcer.xfont),XtRPointer,(XtPointer)NULL },
{XtNforeground,XtCForeground,XtRPixel,sizeof(((XfwfEnforcerRec*)NULL)->xfwfEnforcer.foreground),XtOffsetOf(XfwfEnforcerRec,xfwfEnforcer.foreground),XtRString,(XtPointer)XtDefaultForeground },
{XtNalignment,XtCAlignment,XtRAlignment,sizeof(((XfwfEnforcerRec*)NULL)->xfwfEnforcer.alignment),XtOffsetOf(XfwfEnforcerRec,xfwfEnforcer.alignment),XtRImmediate,(XtPointer)XfwfTop },
{XtNpropagateTarget,XtCPropagateTarget,XtRPropagateTarget,sizeof(((XfwfEnforcerRec*)NULL)->xfwfEnforcer.propagateTarget),XtOffsetOf(XfwfEnforcerRec,xfwfEnforcer.propagateTarget),XtRImmediate,(XtPointer)0 },
{XtNdrawgray,XtCDrawgray,XtRBoolean,sizeof(((XfwfEnforcerRec*)NULL)->xfwfEnforcer.drawgray),XtOffsetOf(XfwfEnforcerRec,xfwfEnforcer.drawgray),XtRImmediate,(XtPointer)FALSE },
};

XfwfEnforcerClassRec xfwfEnforcerClassRec = {
{ /* core_class part */
/* superclass   	*/  (WidgetClass) &xfwfBoardClassRec,
/* class_name   	*/  "XfwfEnforcer",
/* widget_size  	*/  sizeof(XfwfEnforcerRec),
/* class_initialize 	*/  NULL,
/* class_part_initialize*/  _resolve_inheritance,
/* class_inited 	*/  FALSE,
/* initialize   	*/  initialize,
/* initialize_hook 	*/  NULL,
/* realize      	*/  XtInheritRealize,
/* actions      	*/  actionsList,
/* num_actions  	*/  1,
/* resources    	*/  resources,
/* num_resources 	*/  12,
/* xrm_class    	*/  NULLQUARK,
/* compres_motion 	*/  True ,
/* compress_exposure 	*/  XtExposeCompressMultiple ,
/* compress_enterleave 	*/  True ,
/* visible_interest 	*/  False ,
/* destroy      	*/  destroy,
/* resize       	*/  resize,
/* expose       	*/  XtInheritExpose,
/* set_values   	*/  set_values,
/* set_values_hook 	*/  NULL,
/* set_values_almost 	*/  XtInheritSetValuesAlmost,
/* get_values+hook 	*/  NULL,
/* accept_focus 	*/  XtInheritAcceptFocus,
/* version      	*/  XtVersion,
/* callback_private 	*/  NULL,
/* tm_table      	*/  NULL,
/* query_geometry 	*/  XtInheritQueryGeometry,
/* display_acceleator 	*/  XtInheritDisplayAccelerator,
/* extension    	*/  NULL 
},
{ /* composite_class part */
geometry_manager,
change_managed,
insert_child,
XtInheritDeleteChild,
NULL
},
{ /* XfwfCommon_class part */
compute_inside,
XtInherit_total_frame_width,
_expose,
highlight_border,
unhighlight_border,
XtInherit_hilite_callbacks,
XtInherit_would_accept_focus,
XtInherit_traverse,
XtInherit_lighter_color,
XtInherit_darker_color,
XtInherit_set_color,
/* traversal_trans */  NULL ,
/* traversal_trans_small */  NULL ,
/* travMode */  1 ,
},
{ /* XfwfFrame_class part */
 /* dummy */  0
},
{ /* XfwfBoard_class part */
XtInherit_set_abs_location,
},
{ /* XfwfEnforcer_class part */
 /* dummy */  0
},
};
WidgetClass xfwfEnforcerWidgetClass = (WidgetClass) &xfwfEnforcerClassRec;
/*ARGSUSED*/
static void propagateKey(self,event,params,num_params)Widget self;XEvent*event;String*params;Cardinal*num_params;
{
#if 0
    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.propagateTarget && ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.travMode)
      if (event->xkey.state & ControlMask)
	((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.travMode = 0;

    if (!((XfwfEnforcerWidget)self)->xfwfEnforcer.propagateTarget || ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.travMode)
      XtCallActionProc(self, "checkTraverse", event, NULL, 0);
#endif
    
    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.propagateTarget /* && !$travMode */) {
	event->xkey.display	= XtDisplay(((XfwfEnforcerWidget)self)->xfwfEnforcer.propagateTarget);
	event->xkey.send_event	= True;
	event->xkey.window	= XtWindow(((XfwfEnforcerWidget)self)->xfwfEnforcer.propagateTarget);
	XSendEvent(XtDisplay(((XfwfEnforcerWidget)self)->xfwfEnforcer.propagateTarget), XtWindow(((XfwfEnforcerWidget)self)->xfwfEnforcer.propagateTarget),
		   FALSE, KeyPressMask | KeyReleaseMask, event);
    }
}

static void _resolve_inheritance(class)
WidgetClass class;
{
  XfwfEnforcerWidgetClass c = (XfwfEnforcerWidgetClass) class;
  XfwfEnforcerWidgetClass super;
  static CompositeClassExtensionRec extension_rec = {
    NULL, NULLQUARK, XtCompositeExtensionVersion,
    sizeof(CompositeClassExtensionRec), True};
  CompositeClassExtensionRec *ext;
  ext = (XtPointer)XtMalloc(sizeof(*ext));
  *ext = extension_rec;
  ext->next_extension = c->composite_class.extension;
  c->composite_class.extension = ext;
  if (class == xfwfEnforcerWidgetClass) return;
  super = (XfwfEnforcerWidgetClass)class->core_class.superclass;
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void initialize(Widget  request,Widget self,ArgList  args,Cardinal * num_args)
#else
static void initialize(request,self,args,num_args)Widget  request;Widget self;ArgList  args;Cardinal * num_args;
#endif
{
    if (propagate_trans == NULL)
        propagate_trans = XtParseTranslationTable(propagateTranslation);

    XtAugmentTranslations(self, propagate_trans);

    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.label)
      ((XfwfEnforcerWidget)self)->xfwfEnforcer.label = XtNewString(((XfwfEnforcerWidget)self)->xfwfEnforcer.label);
    ((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc = NULL;
    ((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc = NULL;
    /* make_textgc($); - On demand */
    compute_label_size(self);
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void destroy(Widget self)
#else
static void destroy(self)Widget self;
#endif
{
  if (((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc) XtReleaseGC(self, ((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc); ((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc = NULL;
  if (((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc) XtReleaseGC(self, ((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc); ((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc = NULL;
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static Boolean  set_values(Widget  old,Widget  request,Widget self,ArgList  args,Cardinal * num_args)
#else
static Boolean  set_values(old,request,self,args,num_args)Widget  old;Widget  request;Widget self;ArgList  args;Cardinal * num_args;
#endif
{
    Boolean need_redraw = False;

    if ((((XfwfEnforcerWidget)self)->core.background_pixel != ((XfwfEnforcerWidget)old)->core.background_pixel) && ((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc)
	make_graygc(self);

    if (((XfwfEnforcerWidget)old)->xfwfEnforcer.label != ((XfwfEnforcerWidget)self)->xfwfEnforcer.label) {
	if (((XfwfEnforcerWidget)old)->xfwfEnforcer.label)
	  XtFree(((XfwfEnforcerWidget)old)->xfwfEnforcer.label);
	if (((XfwfEnforcerWidget)self)->xfwfEnforcer.label)
	  ((XfwfEnforcerWidget)self)->xfwfEnforcer.label = XtNewString(((XfwfEnforcerWidget)self)->xfwfEnforcer.label);
	need_redraw = True;
    }
    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.font != ((XfwfEnforcerWidget)old)->xfwfEnforcer.font || ((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont != ((XfwfEnforcerWidget)old)->xfwfEnforcer.xfont || ((XfwfEnforcerWidget)self)->xfwfEnforcer.foreground != ((XfwfEnforcerWidget)old)->xfwfEnforcer.foreground) {
	if (((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc) make_textgc(self);
	if (((XfwfEnforcerWidget)self)->xfwfEnforcer.label != NULL)
	    need_redraw = True;
    }
    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.label != ((XfwfEnforcerWidget)old)->xfwfEnforcer.label || ((XfwfEnforcerWidget)self)->xfwfEnforcer.font != ((XfwfEnforcerWidget)old)->xfwfEnforcer.font || ((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont != ((XfwfEnforcerWidget)old)->xfwfEnforcer.xfont)
	compute_label_size(self);

    /* adjust board abs variables */
    if (((XfwfEnforcerWidget)self)->core.width != ((XfwfEnforcerWidget)old)->core.width)
	((XfwfEnforcerWidget)self)->xfwfBoard.abs_width = ((XfwfEnforcerWidget)self)->core.width;
    if (((XfwfEnforcerWidget)self)->core.height != ((XfwfEnforcerWidget)old)->core.height)
	((XfwfEnforcerWidget)self)->xfwfBoard.abs_height = ((XfwfEnforcerWidget)self)->core.height;

    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.label && (((XfwfEnforcerWidget)self)->xfwfEnforcer.drawgray != ((XfwfEnforcerWidget)old)->xfwfEnforcer.drawgray))
      need_redraw = True;

    return need_redraw;
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void _expose(Widget self,XEvent * event,Region  region)
#else
static void _expose(self,event,region)Widget self;XEvent * event;Region  region;
#endif
{
    int w, h;
    Position x, y;

    if (! XtIsRealized(self)) return;
    xfwfBoardClassRec.xfwfCommon_class._expose(self, event, region);
    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.label) {
        GC agc;

	if (!((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc) make_textgc(self);
	
	((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);

	w = max(0, w);
	h = max(0, h);

	if (((XfwfEnforcerWidget)self)->xfwfEnforcer.drawgray && !((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc)
	  make_graygc(self);

	if (((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont)
	  agc = ((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc;
	else
	  agc = ((((XfwfEnforcerWidget)self)->xfwfEnforcer.drawgray && wx_enough_colors(XtScreen(self))) ? ((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc : ((XfwfEnforcerWidget)self)->xfwfEnforcer.textgc);

	switch (((XfwfEnforcerWidget)self)->xfwfEnforcer.alignment) {
	case XfwfTop:
	  XfwfDrawImageString(XtDisplay(self), XtWindow(self), agc,
			      x, wx_ASCENT(((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((wxExtFont)((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont)),
			      ((XfwfEnforcerWidget)self)->xfwfEnforcer.label, strlen(((XfwfEnforcerWidget)self)->xfwfEnforcer.label), NULL, ((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont, !((XfwfEnforcerWidget)self)->xfwfEnforcer.drawgray, NULL);
	  break;
	case XfwfTopLeft:
	  XfwfDrawImageString(XtDisplay(self), XtWindow(self), agc,
			      0, y+wx_ASCENT(((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((wxExtFont)((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont)),
			      ((XfwfEnforcerWidget)self)->xfwfEnforcer.label, strlen(((XfwfEnforcerWidget)self)->xfwfEnforcer.label), NULL, ((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont, !((XfwfEnforcerWidget)self)->xfwfEnforcer.drawgray, NULL);
	  break;
	case XfwfLeft:
	  XfwfDrawImageString(XtDisplay(self), XtWindow(self), agc,
			      0, y+(h-((XfwfEnforcerWidget)self)->xfwfEnforcer.labelHeight)/2+wx_ASCENT(((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((wxExtFont)((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont)),
			      ((XfwfEnforcerWidget)self)->xfwfEnforcer.label, strlen(((XfwfEnforcerWidget)self)->xfwfEnforcer.label), NULL, ((XfwfEnforcerWidget)self)->xfwfEnforcer.font, ((XfwfEnforcerWidget)self)->xfwfEnforcer.xfont, !((XfwfEnforcerWidget)self)->xfwfEnforcer.drawgray, NULL);
	  break;
	}

	if (((XfwfEnforcerWidget)self)->xfwfEnforcer.drawgray && !wx_enough_colors(XtScreen(self))) {
	  XFillRectangle(XtDisplay(self), XtWindow(self), ((XfwfEnforcerWidget)self)->xfwfEnforcer.graygc, 
			 0, y, w + x, h);
	}
    }
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void resize(Widget self)
#else
static void resize(self)Widget self;
#endif
{
    Position x, y;
    int w, h;
    Widget child;

    if (((XfwfEnforcerWidget)self)->composite.num_children == 0) return;
    ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);
    child = ((XfwfEnforcerWidget)self)->composite.children[0];
    w -= 2 * ((XfwfEnforcerWidget)child)->core.border_width;
    h -= 2 * ((XfwfEnforcerWidget)child)->core.border_width;
    XtConfigureWidget(child, x, y, max(1, w), max(1, h), ((XfwfEnforcerWidget)child)->core.border_width);
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void insert_child(Widget  child)
#else
static void insert_child(child)Widget  child;
#endif
{ Widget self = XtParent(child); {
    xfwfBoardClassRec.composite_class.insert_child(child);

    if (child == ((XfwfEnforcerWidget)self)->composite.children[0] && ((XfwfEnforcerWidget)self)->xfwfEnforcer.shrinkToFit) {
	Position x, y; int w, h, cw;

	((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);
	if (((XfwfEnforcerWidget)self)->xfwfEnforcer.alignment == XfwfTop)
	  cw = max(((XfwfEnforcerWidget)child)->core.width, ((XfwfEnforcerWidget)self)->xfwfEnforcer.labelWidth);
	else
	  cw = max(1, ((XfwfEnforcerWidget)child)->core.width);
	w = cw + 2*((XfwfEnforcerWidget)child)->core.border_width + ((XfwfEnforcerWidget)self)->core.width - w;
	h = ((XfwfEnforcerWidget)self)->core.height - h + ((XfwfEnforcerWidget)child)->core.height + 2*((XfwfEnforcerWidget)child)->core.border_width;
	XtVaSetValues(self, XtNwidth, max(1, w), XtNheight, max(1, h), NULL);
    }
}
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void change_managed(Widget self)
#else
static void change_managed(self)Widget self;
#endif
{
    Widget child;
    Position x, y; int w, h;

    if (((XfwfEnforcerWidget)self)->composite.num_children == 0) return;
    ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);
    child = ((XfwfEnforcerWidget)self)->composite.children[0];

    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.shrinkToFit) {
	int selfw, selfh, cw;

	if (((XfwfEnforcerWidget)self)->xfwfEnforcer.alignment == XfwfTop)
	  cw = max(((XfwfEnforcerWidget)child)->core.width, ((XfwfEnforcerWidget)self)->xfwfEnforcer.labelWidth);
	else
	  cw = max(1, ((XfwfEnforcerWidget)child)->core.width);

	selfw = ((XfwfEnforcerWidget)self)->core.width  - w + cw  + 2*((XfwfEnforcerWidget)child)->core.border_width;
	selfh = ((XfwfEnforcerWidget)self)->core.height - h + ((XfwfEnforcerWidget)child)->core.height + 2*((XfwfEnforcerWidget)child)->core.border_width;

	XtVaSetValues(self, XtNwidth, max(1, selfw), XtNheight, max(1, selfh), NULL);
	((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);
    } else  {
	w -= 2 * ((XfwfEnforcerWidget)child)->core.border_width;
	h -= 2 * ((XfwfEnforcerWidget)child)->core.border_width;
    }
    
    XtConfigureWidget(child, x, y, max(1, w), max(1, h), ((XfwfEnforcerWidget)child)->core.border_width);
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static XtGeometryResult  geometry_manager(Widget  child,XtWidgetGeometry * request,XtWidgetGeometry * reply)
#else
static XtGeometryResult  geometry_manager(child,request,reply)Widget  child;XtWidgetGeometry * request;XtWidgetGeometry * reply;
#endif
{ Widget self = XtParent(child); {
    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.shrinkToFit) {
	Position x, y; int w, h;

	/* ask parent to resize (granted because parent is a Board Widget) */
	((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);
	if (request->request_mode & CWWidth) {
	    Dimension cw;

	    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.alignment == XfwfTop)
	      cw = max(request->width, ((XfwfEnforcerWidget)self)->xfwfEnforcer.labelWidth);
	    else
	      cw = max(1, request->width);

	    w = ((XfwfEnforcerWidget)self)->core.width  - w + cw;
	    XtVaSetValues(self, XtNwidth, max(1, w), NULL);
	}
	if (request->request_mode & CWHeight) {
	  h = ((XfwfEnforcerWidget)self)->core.height - h + request->height;
	  XtVaSetValues(self, XtNheight, max(1, h), NULL);
	}
	((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);
	XtConfigureWidget(child, x, y, max(1, w), max(1, h), ((XfwfEnforcerWidget)child)->core.border_width);

	return XtGeometryDone;
    }
    return XtGeometryNo;
}
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void compute_inside(Widget self,Position * x,Position * y,int * w,int * h)
#else
static void compute_inside(self,x,y,w,h)Widget self;Position * x;Position * y;int * w;int * h;
#endif
{
    xfwfBoardClassRec.xfwfCommon_class.compute_inside(self, x, y, w, h);
    /* change sizes to have enough space for the label */
    if (((XfwfEnforcerWidget)self)->xfwfEnforcer.label) {
	switch (((XfwfEnforcerWidget)self)->xfwfEnforcer.alignment) {
	case XfwfTop:
	    *y += ((XfwfEnforcerWidget)self)->xfwfEnforcer.labelHeight + ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness;
	    *h -= ((XfwfEnforcerWidget)self)->xfwfEnforcer.labelHeight + ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness;
	    break;
	case XfwfLeft:
	case XfwfTopLeft:
	    *x += ((XfwfEnforcerWidget)self)->xfwfEnforcer.labelWidth + ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness;
	    *w -= ((XfwfEnforcerWidget)self)->xfwfEnforcer.labelWidth + ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness;
	    break;
	}
    }
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void highlight_border(Widget self)
#else
static void highlight_border(self)Widget self;
#endif
{
    XRectangle  rect[4];
    Position    x, y;
    int   w, h, t;

    if (((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness == 0) return;

    ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);
    x -= ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.total_frame_width(self);
    y -= ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.total_frame_width(self);
    w += 2 * ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.total_frame_width(self);
    h += 2 * ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.total_frame_width(self);

    w = max(0, w);
    h = max(0, h);
    t = 1 /*$highlightThickness */;

    rect[0].x = x+1;
    rect[0].y = y;
    rect[0].width = w-1;
    rect[0].height = t;

    rect[1].x = x;
    rect[1].y = y+1;
    rect[1].width = t;
    rect[1].height = h-2;

    rect[2].x = ((XfwfEnforcerWidget)self)->core.width - t;
    rect[2].y = y+1;
    rect[2].width = t;
    rect[2].height = h-2;

    rect[3].x = x+1;
    rect[3].y = ((XfwfEnforcerWidget)self)->core.height - t;
    rect[3].width = w-2;
    rect[3].height = t;

    if (!((XfwfEnforcerWidget)self)->xfwfCommon.bordergc) create_bordergc(self);
    XFillRectangles(XtDisplay(self), XtWindow(self), ((XfwfEnforcerWidget)self)->xfwfCommon.bordergc, &rect[0], 4);
}
/*ARGSUSED*/
#if NeedFunctionPrototypes
static void unhighlight_border(Widget self)
#else
static void unhighlight_border(self)Widget self;
#endif
{
    Position   x, y;
    int  w, h;

    if (((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness == 0) return;

    ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.compute_inside(self, &x, &y, &w, &h);
    x -= ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.total_frame_width(self);
    y -= ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.total_frame_width(self);
    w += 2 * ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.total_frame_width(self);
    h += 2 * ((XfwfEnforcerWidgetClass)self->core.widget_class)->xfwfCommon_class.total_frame_width(self);

    w = max(w, 0);
    h = max(h, 0);

    XClearArea(XtDisplay(self), XtWindow(self), 
               x, y, w, ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness, False);
    XClearArea(XtDisplay(self), XtWindow(self),
               x, y, ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness, h, False);
    XClearArea(XtDisplay(self), XtWindow(self),
               ((XfwfEnforcerWidget)self)->core.width - ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness, y, 
               ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness, h, False);
    XClearArea(XtDisplay(self), XtWindow(self),
               x, ((XfwfEnforcerWidget)self)->core.height - ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness,
               w, ((XfwfEnforcerWidget)self)->xfwfCommon.highlightThickness, False);
}
