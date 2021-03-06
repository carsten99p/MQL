//+------------------------------------------------------------------+
//|                                           Netsrac - rmsHMAv2.mq4 |
//|                                          Copyright 2017, Netsrac |
//+------------------------------------------------------------------+
//
// - Kurze Beschreibung der Handelsidee
// - 

//
// ---------------------------------------------------------------------------------------------------------------------------

#include <stderror.mqh>
#include <stdlib.mqh>

#property description "rmsHMAv2"
string sDescription="rmsHMAv2";
#property copyright "Copyright 2017, Netsrac"
#property version   "2.02"
//-- Version 1.00 - Ersterstellung
//-- Version 1.01 - Veränderung des Stoploss-Verhaltens: Erster SL ist der jeweils näher am Kurs liegende StopLossFix oder SL nach Markttechnik
//--              - Nachziehen des Stop nach "Markttechnik" abschaltbar
//--              - Prüfen des Candletyps von der Signalkerze bis zur aktuellen eingebaut und abschaltbar gemacht
//--              - Strategieergänzung: Handelsstop nach Loss-Trade und Abstand zum EMA unter Schwelle - wird zurückgenommen, nachdem ein gegenläufiger 
//--                Trade ausgelöst wurde
//-- Version 1.02 - StopLossMin hinzugefügt (Minimaler Stoploss)
//--              - StopLossMax hinzugefügt (Maximaler Stoploss)
//--              - UseProfitclose abschaltbar gemacht
//-- Version 2.00 - Stop und Orderhandling komplett umgeschrieben (Siehe Anleitung)
//-- Version 2.01 - Veränderung der ModifyOrder-Funktion (nunmehr auch bei Forex fehlerfrei)
//-- Version 2.02 - Fehler beim Prüfen eines Gegensignals (Sell) behoben
//--              - Fehler beim Berechnen des Maximal-Stop behoben
//-- 				Kommentar hinzugefügt (Zum Testen von GitHub)
//

#property strict



// Abschaltung des EA nach diesem Termin
//#######################################
datetime dAblauf=D'01.04.2028';
//#######################################

datetime dCurrent=TimeCurrent();

// ############################################################### INPUTS ######################################################

extern string  dummy1         =  "---------------------------------";         // Generelle Angaben
string         sCS_Symbol     =  Symbol();                                    // Genutztes Symbol
extern int     iMaxSlippage   =  3;                                           // (01) Slippage maximal
extern double     dMaxSpread=2.0;                                         // (02) Spread maximal
extern int     iMagicNumber   =  123456;                                      // (03) MagicNumber (Eindeutig!)
extern string  sLabelColor    =  "clrGreen";                                  // (04) Farbe der Label im EA
extern double  dStandardLot   =  0.1;                                         // (05) Standard-Lotgröße ohne MM
extern bool    bUseMarkttechnik = FALSE;                                      // (06) Stoploss Nachziehen nach Markttechnik?
extern bool    bUseHandelsstop = TRUE;                                        // (07) Handelsstop-Mechanismus nutzen?
extern bool    bUseCandleTypes = TRUE;                                        // (08) Typ der Signalkerze(n) prüfen?
extern bool    bUseProfitClose = TRUE;                                        // (09) Nur im Gewinn schließen?
extern string  dummy2         =  "---------------------------------";         // Einstiegsbedingungen
extern int     iHMAPeriode    =  20;                                          // (10) HMA Periode
extern int     iHMAMethode    =  1;                                           // (11) HMA Methode
int iHMAPrice = 0;
int iHMAShift = 0;
extern int     iEMAPeriode    = 100;                                          // (12) Periode des Kontroll-EMA (Tradestop)
extern double  dEMAAbstand    = 25;                                           // (13) Abstand zum Kontroll-EMA (Tradestop)
extern int     iSignalBar=1;                                                  // (14) Open nach Close dieser Bar

extern string  dummy4         =  "---------------------------------";         // Trademanagement
extern double  dStopLossMin   =  0;                                           // (15) Minimum Stop loss bei Order
extern double  dStopLossMax   =  0;                                           // (16) Maximaler Stop loss bei Order
extern double  dStopLossFix   =  0;                                           // (17) Fester Stop loss bei Order
extern double  dStopLossOffset=  0;                                           // (18) Pips über/unter SL bei Order und Nachziehen
extern int     iBarsLookBack  =  10;                                          // (19) Anzahl Bars für SL nach Markttechnik (MT)
extern double  dTrailStopLossMin   =  0;                                      // (20) Minimum Stop loss beim Nachziehen des SL
                                                                              //extern double  dTrailStopLossMax   =  0;                                      // (21) Maximaler Stop loss beim Nachziehen des SL     
extern double  dCRV=5;                                                        // (22) CRV (Verhältnis TP zu SL) (0=ohne TP)
extern double  dTakeProfitFix=10;                                             // (23) Fester Takeprofit bei Order

extern string  dummy6="---------------------------------";                    // Trade-Kommentare
extern string  sCommentBuy="Buy rmsHMA";                                      // (24) Kommentar für Buy
extern string  sCommentSell="Sell rmsHMA";                                    // (25) Kommentar für Sell

extern string  dummy7="---------------------------------";                    // Alarmierung
extern bool    bAlert         = TRUE;                                         // (26) Alarmierung bei Order
extern bool    bOrder         = TRUE;                                         // (27) Order ausführen?
extern bool    bUseLogging = TRUE;                                            // (28) Fehlerlogging anschalten?
                                                                              // -------------------------------------------------------------- INPUTS ------------------------------------------------------

// ########################################################## GLOBALE VARIABLEN ################################################
//-- Globale Variablen
string sLastError= "";
long lLabelColor = StringToColor(sLabelColor);
double point;
int iTimeFrame=Period();
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ---------------------------------------------------------- GLOBALE VARIABLEN ------------------------------------------------

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create timer
   EventSetTimer(60);

// point ist der Multiplikator, damit feste Pip-Werte verwendet werden können
// Wird also 20 * point gerechnet, ergibt sich beim DAX ein Wert von 20.0 (point 1.0) - beim EURUSD wären das dann 0.0020 (point 0.0001)
   point=Point;
   if((Digits==3) || (Digits==5) || (Digits==1))
     {
      point*=10;
     }
   if(bUseLogging)
     {
      Alarm("INIT: point=",2);
      Alarm(DoubleToString(point),2);
     }

//-- Label Title generieren
   ObjectCreate(0,"csTitle",OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,"csTitle",OBJPROP_CORNER,0);
   ObjectSetInteger(0,"csTitle",OBJPROP_XDISTANCE,300);
   ObjectSetInteger(0,"csTitle",OBJPROP_YDISTANCE,0);
   ObjectSetInteger(0,"csTitle",OBJPROP_COLOR,lLabelColor);
   ObjectSetString(0,"csTitle",OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,"csTitle",OBJPROP_FONTSIZE,12);
   ObjectSetString(0,"csTitle",OBJPROP_TEXT,sDescription);

//-- Label Zeit generieren
   ObjectCreate(0,"csTime",OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,"csTime",OBJPROP_CORNER,0);
   ObjectSetInteger(0,"csTime",OBJPROP_XDISTANCE,400);
   ObjectSetInteger(0,"csTime",OBJPROP_YDISTANCE,0);
   ObjectSetInteger(0,"csTime",OBJPROP_COLOR,lLabelColor);
   ObjectSetString(0,"csTime",OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,"csTime",OBJPROP_FONTSIZE,10);

//-- Label Spread generieren
   ObjectCreate(0,"csSpread",OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,"csSpread",OBJPROP_CORNER,350);
   ObjectSetInteger(0,"csSpread",OBJPROP_XDISTANCE,400);
   ObjectSetInteger(0,"csSpread",OBJPROP_YDISTANCE,15);
   ObjectSetInteger(0,"csSpread",OBJPROP_COLOR,lLabelColor);
   ObjectSetString(0,"csSpread",OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,"csSpread",OBJPROP_FONTSIZE,10);

//-- Label Letzter Fehler generieren
   ObjectCreate(0,"csLE",OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,"csLE",OBJPROP_CORNER,0);
   ObjectSetInteger(0,"csLE",OBJPROP_XDISTANCE,400);
   ObjectSetInteger(0,"csLE",OBJPROP_YDISTANCE,30);
   ObjectSetInteger(0,"csLE",OBJPROP_COLOR,lLabelColor);
   ObjectSetString(0,"csLE",OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,"csLE",OBJPROP_FONTSIZE,10);

//-- Label Status generieren
   ObjectCreate(0,"csSTAT",OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,"csSTAT",OBJPROP_CORNER,0);
   ObjectSetInteger(0,"csSTAT",OBJPROP_XDISTANCE,550);
   ObjectSetInteger(0,"csSTAT",OBJPROP_YDISTANCE,0);
   ObjectSetInteger(0,"csSTAT",OBJPROP_COLOR,lLabelColor);
   ObjectSetString(0,"csSTAT",OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,"csSTAT",OBJPROP_FONTSIZE,10);
   
//-- Label Status2 generieren
   ObjectCreate(0,"csSTAT2",OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,"csSTAT2",OBJPROP_CORNER,0);
   ObjectSetInteger(0,"csSTAT2",OBJPROP_XDISTANCE,550);
   ObjectSetInteger(0,"csSTAT2",OBJPROP_YDISTANCE,15);
   ObjectSetInteger(0,"csSTAT2",OBJPROP_COLOR,lLabelColor);
   ObjectSetString(0,"csSTAT2",OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,"csSTAT2",OBJPROP_FONTSIZE,10);
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
//ObjectsDeleteAll(0);
   Print(sLastError);

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

// ############## Variablen festlegen ####################################################
   int iErrorCount=0; //Fehlerspeicher
   double dHMAnr[10],dHMAup[10],dHMAdn[10];
   string sCandleType[10];
   double dBSL=0,dSSL=0,dBTP=0,dSTP=0;
   double dTBSL=0,dTSSL=0;
   double dT2BSL=0,dT2SSL=0;
   double dMINBSL=0,dMINSSL=0,dMAXBSL=0,dMAXSSL=0;
   double dEMA=0;
   double dTempMTStopBuy1=0,dTempMTStopSell1=0;
   double dTempMTStopBuy2=0,dTempMTStopSell2=0;
   int i;
   bool bHandelsstopBuy=FALSE,bHandelsstopSell=FALSE;
   bool bOrderClose=FALSE;
   bool bCandleRightDirection=TRUE;

   string sTimeFrame;

   switch(Period())
     {
      case 1:
         sTimeFrame="M1";
         break;
      case 2:
         sTimeFrame="M2";
         break;
      case 3:
         sTimeFrame="M3";
         break;
      case 4:
         sTimeFrame="M4";
         break;
      case 5:
         sTimeFrame="M5";
         break;
      case 6:
         sTimeFrame="M6";
         break;
      case 10:
         sTimeFrame="M10";
         break;
      case 12:
         sTimeFrame="M12";
         break;
      case 15:
         sTimeFrame="M15";
         break;
      case 20:
         sTimeFrame="M20";
         break;
      case 30:
         sTimeFrame="M30";
         break;
      case 60:
         sTimeFrame="H1";
         break;
      case 240:
         sTimeFrame="H4";
         break;
      case 1440:
         sTimeFrame="D1";
         break;
      default:
         sTimeFrame=StringConcatenate("MR",PERIOD_CURRENT);
         break;
     }

   ArrayInitialize(dHMAnr,0);
   ArrayInitialize(dHMAup,0);
   ArrayInitialize(dHMAdn,0);
//ArrayInitialize(sCandleType,"");
   string sAlarm="";

// ############## Prüfen, ob Periode zum Initwert passt ##################################
   int iTimeFrameCurrent=Period();
   if(iTimeFrame!=iTimeFrameCurrent)
     {
      sAlarm = "Achtung! Aktueller Timeframe passt nicht zum Initialwert: ";
      sAlarm+= IntegerToString(iTimeFrame);
      Alarm(sAlarm,2);
     }

//-- Label Time befüllen
   string sTemp="Serverzeit: ";
   sTemp+=TimeToString(TimeCurrent(),TIME_MINUTES);
   ObjectSetString(0,"csTime",OBJPROP_TEXT,sTemp);

   sTemp = "Spread: ";
   sTemp+= DoubleToString(Spread(sCS_Symbol),2);
   ObjectSetString(0,"csSpread",OBJPROP_TEXT,sTemp);

// Fehler ausgeben im Label - Alternativ Print
   sTemp = "Fehler: ";
   sTemp+= IntegerToString(iErrorCount);
   if(dCurrent>dAblauf) sTemp+=" (EA ist abgelaufen)";
   ObjectSetString(0,"csLE",OBJPROP_TEXT,sTemp);
   
      // Statuszeile zusammensetzen und anzeigen
      sTemp="Status: ";
      if(TotalMarketOrdersCount(iMagicNumber)>0)
        {
         sTemp += "Trade läuft.";
        }
      else sTemp+="Warte auf Signal";
      ObjectSetString(0,"csSTAT",OBJPROP_TEXT,sTemp);

// #################################################################################################### TRADE-CODE ###################

   if(NewBar() && dCurrent<dAblauf)
     {

      // Prüfen, ob ein Handelsstop verhängt werden muss (Letzter Trade im Verlust und Abstand zum EMA
      if(bUseHandelsstop==TRUE)
        {
         dEMA=iMA(sCS_Symbol,PERIOD_CURRENT,iEMAPeriode,0,MODE_EMA,PRICE_CLOSE,0);
         if(CheckLastTrade(sCS_Symbol,iMagicNumber)=="BUY LOSS" && (dEMA-PreisBidVerkaufen(sCS_Symbol))/point>dEMAAbstand)
           {
            bHandelsstopBuy=TRUE;
            if(bUseLogging)
              {
               Alarm("ONTICK: Handelsstop Buy",2);
              }
              } else {
            bHandelsstopBuy=FALSE;
           }

         if(CheckLastTrade(sCS_Symbol,iMagicNumber)=="SELL LOSS" && (PreisBidVerkaufen(sCS_Symbol)-dEMA)/point>dEMAAbstand)
           {
            bHandelsstopSell=TRUE;
            if(bUseLogging)
              {
               Alarm("ONTICK: Handelsstop Sell",2);
              }
              } else {
            bHandelsstopSell=FALSE;
           }
        }

      // HMA der letzten 10 Perioden auslesen
      for(i=0;i<10;i++)
        {
         dHMAnr[i] = iCustom(sCS_Symbol,iTimeFrame,"IFX-HMA",iHMAPeriode,iHMAMethode,iHMAPrice,iHMAShift,0,i); //Normalkurs
         dHMAup[i] = iCustom(sCS_Symbol,iTimeFrame,"IFX-HMA",iHMAPeriode,iHMAMethode,iHMAPrice,iHMAShift,1,i); //UP
         dHMAdn[i] = iCustom(sCS_Symbol,iTimeFrame,"IFX-HMA",iHMAPeriode,iHMAMethode,iHMAPrice,iHMAShift,2,i); //DOWN
         sCandleType[i]=CheckCandleType(iOpen(sCS_Symbol,PERIOD_CURRENT,i),iClose(sCS_Symbol,PERIOD_CURRENT,i));
        }

      // Stoploss und TakeProfit berechnen
      // Zunächst den Minimalen und den Maximalen Stop berechnen (Wenn diese Werte gesetzt sind)
      if(dStopLossMin>0)
        {
         dMINBSL = PreisAskKaufen(sCS_Symbol)-dStopLossMin*point;
         dMINSSL = PreisBidVerkaufen(sCS_Symbol)+dStopLossMin*point;
        }
      if(dStopLossMax>0)
        {
         dMAXBSL = PreisAskKaufen(sCS_Symbol)-dStopLossMax*point;
         dMAXSSL = PreisBidVerkaufen(sCS_Symbol)+dStopLossMax*point;
        }

      // Ab hier werden die verschiedenen Möglichkeiten errechnet (Siehe Beschreibung)
      if(dStopLossFix>0 && dTakeProfitFix==0 && dCRV==0)
        {
         // Fester Stop + Ohne TP
         dBSL = PreisAskKaufen(sCS_Symbol)-(dStopLossFix+dStopLossOffset)*point;
         dSSL = PreisBidVerkaufen(sCS_Symbol)+(dStopLossFix+dStopLossOffset)*point;
         if(dStopLossMin>0 && dBSL<dMINBSL) dBSL = dMINBSL;
         if(dStopLossMax>0 && dBSL<dMAXBSL) dBSL = dMAXBSL;
         if(dStopLossMin>0 && dSSL>dMINSSL) dSSL = dMINSSL;
         if(dStopLossMax>0 && dSSL>dMAXSSL) dSSL = dMAXSSL;
        }
      if(dStopLossFix>0 && dTakeProfitFix>0)
        {
         // Fester Stop + Fester TP
         dBSL = PreisAskKaufen(sCS_Symbol)-(dStopLossFix+dStopLossOffset)*point;
         dSSL = PreisBidVerkaufen(sCS_Symbol)+(dStopLossFix+dStopLossOffset)*point;
         if(dStopLossMin>0 && dBSL<dMINBSL) dBSL = dMINBSL;
         if(dStopLossMax>0 && dBSL<dMAXBSL) dBSL = dMAXBSL;
         if(dStopLossMin>0 && dSSL>dMINSSL) dSSL = dMINSSL;
         if(dStopLossMax>0 && dSSL>dMAXSSL) dSSL = dMAXSSL;
         dBTP = PreisAskKaufen(sCS_Symbol)+dTakeProfitFix*point;
         dSTP = PreisBidVerkaufen(sCS_Symbol)-dTakeProfitFix*point;
        }
      if(dStopLossFix>0 && dCRV>0)
        {
         // Fester Stop + Fester CRV
         dBSL = PreisAskKaufen(sCS_Symbol)-(dStopLossFix+dStopLossOffset)*point;
         dSSL = PreisBidVerkaufen(sCS_Symbol)+(dStopLossFix+dStopLossOffset)*point;
         if(dStopLossMin>0 && dBSL<dMINBSL) dBSL = dMINBSL;
         if(dStopLossMax>0 && dBSL<dMAXBSL) dBSL = dMAXBSL;
         if(dStopLossMin>0 && dSSL>dMINSSL) dSSL = dMINSSL;
         if(dStopLossMax>0 && dSSL>dMAXSSL) dSSL = dMAXSSL;
         dBTP=PreisAskKaufen(sCS_Symbol)+((PreisAskKaufen(sCS_Symbol)-dBSL)*dCRV);
         dSTP=PreisBidVerkaufen(sCS_Symbol)-((dSSL-PreisBidVerkaufen(sCS_Symbol))*dCRV);
        }
      if(dStopLossFix==0 && dTakeProfitFix>0 && iBarsLookBack>0)
        {
         // Variabler Stop + Fester Takeprofit
         dBSL = LetztesTiefNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
         dSSL = LetztesHochNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
         if(dStopLossMin>0 && dBSL<dMINBSL) dBSL = dMINBSL;
         if(dStopLossMax>0 && dBSL<dMAXBSL) dBSL = dMAXBSL;
         if(dStopLossMin>0 && dSSL>dMINSSL) dSSL = dMINSSL;
         if(dStopLossMax>0 && dSSL>dMAXSSL) dSSL = dMAXSSL;
         dBTP = PreisAskKaufen(sCS_Symbol)+dTakeProfitFix*point;
         dSTP = PreisBidVerkaufen(sCS_Symbol)-dTakeProfitFix*point;
        }
      if(dStopLossFix==0 && dCRV>0 && iBarsLookBack>0)
        {
         // Variabler Stop + Variabler Takeprofit
         dBSL = LetztesTiefNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
         dSSL = LetztesHochNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
         if(dStopLossMin>0 && dBSL<dMINBSL) dBSL = dMINBSL;
         if(dStopLossMax>0 && dBSL<dMAXBSL) dBSL = dMAXBSL;
         if(dStopLossMin>0 && dSSL>dMINSSL) dSSL = dMINSSL;
         if(dStopLossMax>0 && dSSL>dMAXSSL) dSSL = dMAXSSL;
         dBTP=PreisAskKaufen(sCS_Symbol)+((PreisAskKaufen(sCS_Symbol)-dBSL)*dCRV);
         dSTP=PreisBidVerkaufen(sCS_Symbol)-((dSSL-PreisBidVerkaufen(sCS_Symbol))*dCRV);
        }
      if(dStopLossFix==0 && dCRV==0 && dTakeProfitFix==0 && iBarsLookBack>0)
        {
         // Variabler Stop + Ohne Takeprofit
         dBSL = LetztesTiefNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
         dSSL = LetztesHochNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
         if(dStopLossMin>0 && dBSL<dMINBSL) dBSL = dMINBSL;
         if(dStopLossMax>0 && dBSL<dMAXBSL) dBSL = dMAXBSL;
         if(dStopLossMin>0 && dSSL>dMINSSL) dSSL = dMINSSL;
         if(dStopLossMax>0 && dSSL>dMAXSSL) dSSL = dMAXSSL;
        }

      //#####################################################################################################

      dBSL = NormalizeDouble(dBSL,Digits);
      dSSL = NormalizeDouble(dSSL,Digits);

      //Festlegen, ob im Falle eines Gegensignals geschlossen und neu geöffnet werden soll
      if(TotalOrderProfit(iMagicNumber)>0 && bUseProfitClose==TRUE) bOrderClose=TRUE;
      if(bUseProfitClose==FALSE) bOrderClose=TRUE;

      // Ein Wechsel der Richtung wurde erkannt (Sowohl UP als auch DOWN im HMA gesetzt)
      if(dHMAup[iSignalBar+1]==dHMAnr[iSignalBar+1] && dHMAdn[iSignalBar+1]==dHMAnr[iSignalBar+1])
        {

         if(bUseLogging)
           {
            Alarm("ONTICK: Signal erkannt",2);
           }

         // Im HMA sind UP und NORMAL der Signalbar identisch - damit hat dort ein Wechsel zu UP stattgefunden
         if(dHMAup[iSignalBar]==dHMAnr[iSignalBar])
           {
            if(bUseLogging)
              {
               Alarm("ONTICK: Signal UP",2);
              }
            //Wenn Candletyperkennung an ist - die Typen auf "richtige" Richtung prüfen
            if(bUseCandleTypes==TRUE)
              {
               for(i=1;i<=iSignalBar;i++)
                 {
                  if(sCandleType[i]=="sell") bCandleRightDirection=FALSE;
                  if(bUseLogging)
                    {
                     Alarm(sCandleType[i],2);
                    }
                 }
              }
            //Es gibt bereits eine laufende Sell-Order und der Profit dieser Order ist positiv - Schließen und ggf. Buy neu eröffnen
            if(TotalMarketSellOrdersCount(iMagicNumber)>0 && bOrderClose==TRUE)
              {
               if(bUseLogging)
                 {
                  Alarm("ONTICK: Signal UP - Close Order",2);
                 }
               SchliesseAlleOrders(sCS_Symbol,iMagicNumber,iMaxSlippage);
               // Prüfen, ob Spread unter Maxspread, ob ein Handelsstop gilt und ob die letzte Kerze in die richtige Richtung geht
               if(dMaxSpread>=Spread(sCS_Symbol) && bHandelsstopBuy==FALSE && bCandleRightDirection==TRUE)
                 {
                  if(bOrder)
                    {
                     if(bUseLogging)
                       {
                        Alarm("ONTICK: Open Order after Close",2);
                       }
                     EroeffneMarketOrder(sCS_Symbol,"buy",dStandardLot,dBSL,dBTP,iMaxSlippage,iMagicNumber,sCommentBuy);
                    }
                  if(bAlert)
                    {
                     sAlarm=StringConcatenate(sTimeFrame," ",sCS_Symbol," Buy");
                     Alarm(sAlarm,3);
                    }
                  // ##################################### zu überprüfen, ob tatsächlich nach einem Gegensignal das gegenüberliegende wieder frei gegeben wird
                  bHandelsstopSell=FALSE;
                 }
              }
            else if(TotalMarketOrdersCount(iMagicNumber)==0 && dMaxSpread>=Spread(sCS_Symbol) && bHandelsstopBuy==FALSE && bCandleRightDirection==TRUE)
              {
               if(bOrder)
                 {
                  if(bUseLogging)
                    {
                     Alarm("ONTICK: Open Order without Close",2);
                    }
                  EroeffneMarketOrder(sCS_Symbol,"buy",dStandardLot,dBSL,dBTP,iMaxSlippage,iMagicNumber,sCommentBuy);
                 }
               if(bAlert)
                 {
                  sAlarm=StringConcatenate(sTimeFrame," ",sCS_Symbol," Buy");
                  Alarm(sAlarm,3);
                 }
               bHandelsstopSell=FALSE;
              }
           }
         // Im HMA sind DN und NORMAL der Signalbar identisch - damit hat dort ein Wechsel zu DOWN stattgefunden
         if(dHMAdn[iSignalBar]==dHMAnr[iSignalBar])
           {
            if(bUseLogging)
              {
               Alarm("ONTICK: Signal DN",2);
              }
            //Wenn Candletyperkennung an ist - die Typen auf "richtige" Richtung prüfen
            if(bUseCandleTypes==TRUE)
              {
               for(i=1;i<=iSignalBar;i++)
                 {
                  if(sCandleType[i]=="buy") bCandleRightDirection=FALSE;
                  if(bUseLogging)
                    {
                     Alarm(sCandleType[i],2);
                    }
                 }
              }
            //Es gibt bereits eine laufende Buy-Order und der Profit dieser Order ist positiv - Schließen und ggf. Sell neu eröffnen
            if(TotalMarketBuyOrdersCount(iMagicNumber)>0 && bOrderClose==TRUE)
              {
               if(bUseLogging)
                 {
                  Alarm("ONTICK: Signal DN - Close Order",2);
                 }
               SchliesseAlleOrders(sCS_Symbol,iMagicNumber,iMaxSlippage);
               // Prüfen, ob Spread unter Maxspread, ob ein Handelsstop gilt und ob die letzte Kerze in die richtige Richtung geht
               if(dMaxSpread>=Spread(sCS_Symbol) && bHandelsstopSell==FALSE && bCandleRightDirection==TRUE)
                 {
                  if(bOrder)
                    {
                     if(bUseLogging)
                       {
                        Alarm("ONTICK: Open Order after Close",2);
                       }
                     EroeffneMarketOrder(sCS_Symbol,"sell",dStandardLot,dSSL,dSTP,iMaxSlippage,iMagicNumber,sCommentSell);
                    }
                  if(bAlert)
                    {
                     sAlarm=StringConcatenate(sTimeFrame," ",sCS_Symbol," Sell");
                     Alarm(sAlarm,3);
                    }
                  bHandelsstopBuy=FALSE;
                 }
              }
            else if(TotalMarketOrdersCount(iMagicNumber)==0 && dMaxSpread>=Spread(sCS_Symbol) && bHandelsstopSell==FALSE && bCandleRightDirection==TRUE)
              {
               if(bOrder)
                 {
                  if(bUseLogging)
                    {
                     Alarm("ONTICK: Open Order without Close",2);
                    }
                  EroeffneMarketOrder(sCS_Symbol,"sell",dStandardLot,dSSL,dSTP,iMaxSlippage,iMagicNumber,sCommentSell);
                 }
               if(bAlert)
                 {
                  sAlarm=StringConcatenate(sTimeFrame," ",sCS_Symbol," Sell");
                  Alarm(sAlarm,3);
                 }
               bHandelsstopBuy=FALSE;
              }
           }
        }
     }

// Buyorder SL anpassen (Wenn iBarsLookBack > 0)
   if(iBarsLookBack>0 && bUseMarkttechnik==TRUE && TotalMarketBuyOrdersCount(iMagicNumber)>0)
     {
     if(dTrailStopLossMin>0) dTempMTStopBuy1 = PreisBidVerkaufen(sCS_Symbol) - dTrailStopLossMin;
     if(dTrailStopLossMin==0) dTempMTStopBuy1 = LetztesTiefNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
      dTempMTStopBuy2 = LetztesTiefNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
      if(dTempMTStopBuy1>dTempMTStopBuy2)
        {
         ModifyTrailingStop(sCS_Symbol,dTempMTStopBuy2,iMagicNumber);
        }
      else
        {
         ModifyTrailingStop(sCS_Symbol,dTempMTStopBuy1,iMagicNumber);
        }
     }
// Sellorder SL anpassen
   if(iBarsLookBack>0 && bUseMarkttechnik==TRUE && TotalMarketSellOrdersCount(iMagicNumber)>0)
     {
     if(dTrailStopLossMin>0) dTempMTStopSell1 = PreisAskKaufen(sCS_Symbol) + dTrailStopLossMin;
     if(dTrailStopLossMin==0) dTempMTStopSell1 = LetztesHochNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
      dTempMTStopSell2 = LetztesHochNachMarkttechnik(sCS_Symbol,iTimeFrame,iBarsLookBack,0,dStopLossOffset);
      if(dTempMTStopSell1<dTempMTStopSell2)
        {
         ModifyTrailingStop(sCS_Symbol,dTempMTStopSell2,iMagicNumber);
        }
      else
        {
         ModifyTrailingStop(sCS_Symbol,dTempMTStopSell1,iMagicNumber);
        }
     }

// #################################################################################################### TRADE-CODE ###################

   return;


  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
string sTemp;
   if(TotalMarketOrdersCount(iMagicNumber)>0)
        {
         sTemp += "Profit aktuelle Order: ";
         sTemp += DoubleToString(TotalOrderProfit(iMagicNumber),2);
        }
      else sTemp+="...";
      ObjectSetString(0,"csSTAT2",OBJPROP_TEXT,sTemp);
      
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
//---
   double ret=0.0;
//---

//---
   return(ret);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

// ########################################################## TotalOrdersCount ################################################
// Zählt alle Orders mit einer spezifischen Magicnumber. Typ der Order ist dabei egal.

int TotalOrdersCount(int MagicNumber)
  {
   int result=0;
   int retr=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      retr=OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
      if(OrderMagicNumber()==MagicNumber) result++;

     }
   return (result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ########################################################## TotalOrderProfit ################################################
// Gibt den Gewinn aller derzeit offenen Positionen einer speziellen Magicnumber zurück.

double TotalOrderProfit(int MagicNumber)
  {
   double profit=0;
   int retr=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      retr=OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
      if(OrderMagicNumber()==MagicNumber) profit+=OrderProfit();

     }
   return (profit);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### TotalStopOrdersCount ################################################ 
// Zählt alle Stop-Orders mit einer spezifischen Magicnumber.

int TotalStopOrdersCount(int MagicNumber)
  {
   int result=0;
   int retr=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      retr=OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
      if(OrderMagicNumber()==MagicNumber && (OrderType()==OP_BUYSTOP || OrderType()==OP_SELLSTOP)) result++;

     }
   return (result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### TotalLimitOrdersCount ################################################
// Zählt alle Stop-Orders mit einer spezifischen Magicnumber.
int TotalLimitOrdersCount(int MagicNumber)
  {
   int result=0;
   int retr=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      retr=OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
      if(OrderMagicNumber()==MagicNumber && (OrderType()==OP_SELLLIMIT || OrderType()==OP_BUYLIMIT)) result++;

     }
   return (result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### TotalMarketOrdersCount ################################################
// Zählt alle Market-Orders mit einer spezifischen Magicnumber.
int TotalMarketOrdersCount(int MagicNumber)
  {
   int result=0;
   int retr=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      retr=OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
      if(OrderMagicNumber()==MagicNumber && (OrderType()==OP_SELL || OrderType()==OP_BUY)) result++;

     }
   return (result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### TotalMarketBuyOrdersCount ################################################
// Zählt alle Market-Buy Orders mit einer spezifischen Magicnumber.
int TotalMarketBuyOrdersCount(int MagicNumber)
  {
   int result=0;
   int retr=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      retr=OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
      if(OrderMagicNumber()==MagicNumber && OrderType()==OP_BUY) result++;

     }
   return (result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### TotalMarketSellOrdersCount ################################################
// Zählt alle Market-Sell Orders mit einer spezifischen Magicnumber.
int TotalMarketSellOrdersCount(int MagicNumber)
  {
   int result=0;
   int retr=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      retr=OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
      if(OrderMagicNumber()==MagicNumber && OrderType()==OP_SELL) result++;

     }
   return (result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### EroeffneMarketOrder ################################################
// Eröffnet eine Market-Order.
int EroeffneMarketOrder(string sSymbol,string sOrderType,double dSLot,double StopLoss,double TakeProfit,int Slippage,int MagicNumber,string sComment)
  {
   int FehlerCode=0;
   int Ticketnummer=0;
   if(sOrderType=="buy")
     {
      while(IsTradeContextBusy()) Sleep(10);
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      Ticketnummer=0;
      while(Ticketnummer<=0)
        {
         RefreshRates();
         Ticketnummer=OrderSend(sSymbol,OP_BUY,dSLot,Ask,Slippage,StopLoss,TakeProfit,sComment,MagicNumber,0,Green);
         if(Ticketnummer==-1){FehlerCode=GetLastError();}
         if(Wiederholungen<=MaximaleWiederholungen && 
            FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
         else break;
        }
      if(Ticketnummer==-1)
        {
         FehlerCode=GetLastError();
         string FehlerBeschreibung=ErrorDescription(FehlerCode);
         string FehlerAusgabe=StringConcatenate("Eröffnung Kauf-Order:",FehlerCode,": ",FehlerBeschreibung);
         Print(FehlerAusgabe);
        }
     }
   if(sOrderType=="sell")
     {
      while(IsTradeContextBusy()) Sleep(10);
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      Ticketnummer=0;
      while(Ticketnummer<=0)
        {
         RefreshRates();
         Ticketnummer=OrderSend(sSymbol,OP_SELL,dSLot,Bid,Slippage,StopLoss,TakeProfit,sComment,MagicNumber,0,Green);
         if(Ticketnummer==-1){FehlerCode=GetLastError();}
         if(Wiederholungen<=MaximaleWiederholungen && 
            FehlerPruefung(FehlerCode)==true) { Wiederholungen++;}
         else break;
        }
      if(Ticketnummer==-1)
        {
         FehlerCode=GetLastError();
         string FehlerBeschreibung=ErrorDescription(FehlerCode);
         string FehlerAusgabe=StringConcatenate("Eröffnung Kauf-Order:",FehlerCode,": ",FehlerBeschreibung);
         Print(FehlerAusgabe);
        }
     }

   return(Ticketnummer);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### EroeffneBuyStopOrder ################################################
// Eröffnet eine Buy-Stop Order.
//
int EroeffneBuyStopOrder(string sSymbol,double dEntry,int iSlippage,double dfStopLoss,double dfTakeProfit,double dSLot,string sComment)
  {
   int Ticketnummer=0;
   int FehlerCode=0;

   while(IsTradeContextBusy()) Sleep(10);

   int Wiederholungen=0;
   int MaximaleWiederholungen=10;
   while(Ticketnummer<=0)
     {
      RefreshRates();
      Ticketnummer=OrderSend(sSymbol,OP_BUYSTOP,dSLot,dEntry,iSlippage,dfStopLoss,dfTakeProfit,sComment,iMagicNumber,0,clrBlue);
      if(Ticketnummer==-1){FehlerCode=GetLastError();}
      if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true)
        {
         Wiederholungen++;
        }
      else break;
     }
   if(Ticketnummer==-1)
     {
      FehlerCode=GetLastError();
      string FehlerBeschreibung=ErrorDescription(FehlerCode);
      string FehlerAusgabe=StringConcatenate("Eröffnung Stop-Kauf-Order:",FehlerCode,": ",FehlerBeschreibung);
      sLastError=FehlerAusgabe;
     }

   return(Ticketnummer);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### EroeffneSellStopOrder ################################################
// Eröffnet eine Sell-Stop Order.
//
int EroeffneSellStopOrder(string sSymbol,double dEntry,int iSlippage,double dfStopLoss,double dfTakeProfit,double dSLot,string sComment)
  {

   int Ticketnummer=0;
   int FehlerCode=0;

   while(IsTradeContextBusy()) Sleep(10);

   int Wiederholungen=0;
   int MaximaleWiederholungen=10;
   while(Ticketnummer<=0)
     {
      RefreshRates();
      Ticketnummer=OrderSend(sSymbol,OP_SELLSTOP,dSLot,dEntry,iSlippage,dfStopLoss,dfTakeProfit,sComment,iMagicNumber,0,clrRed);
      if(Ticketnummer==-1){FehlerCode=GetLastError();}
      if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true)
        {
         Wiederholungen++;
        }
      else break;
     }
   if(Ticketnummer==-1)
     {
      FehlerCode=GetLastError();
      string FehlerBeschreibung=ErrorDescription(FehlerCode);
      string FehlerAusgabe=StringConcatenate("Eröffnung Stop-Kauf-Order:",FehlerCode,": ",FehlerBeschreibung);
      sLastError=FehlerAusgabe;
     }

   return(Ticketnummer);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### EroeffneLimitOrder ################################################
// Eröffnet eine Limit-Stop Order.
//
int EroeffneLimitOrder(string sfSymbol,double dfEroeffnungskurs,double dfLot,string sfHandelsrichtung,double dfStopLoss,double dfTakeProfit,int ifSlippage,int ifMagicNumber,string sComment)
  {
   int Ticketnummer=0;
   int FehlerCode=0;
   if(sfHandelsrichtung=="buy")
     {
      while(IsTradeContextBusy()) Sleep(10);
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      while(Ticketnummer<=0)
        {
         RefreshRates();
         Ticketnummer=OrderSend(sfSymbol,OP_BUYLIMIT,dfLot,dfEroeffnungskurs,ifSlippage,dfStopLoss,dfTakeProfit,sComment,ifMagicNumber,0,Green);
         if(Ticketnummer==-1){FehlerCode=GetLastError();}
         if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
         else break;
        }
      if(Ticketnummer==-1)
        {
         FehlerCode=GetLastError();
         string FehlerBeschreibung=ErrorDescription(FehlerCode);
         string FehlerAusgabe=StringConcatenate("Eröffnung Limit-Kauf-Order:",FehlerCode,": ",FehlerBeschreibung);
         sLastError=FehlerAusgabe;
        }
     }
   if(sfHandelsrichtung=="sell")
     {
      while(IsTradeContextBusy()) Sleep(10);
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      while(Ticketnummer<=0)
        {
         RefreshRates();
         Ticketnummer=OrderSend(sfSymbol,OP_SELLLIMIT,dfLot,dfEroeffnungskurs,ifSlippage,dfStopLoss,dfTakeProfit,sComment,ifMagicNumber,0,Green);
         if(Ticketnummer==-1){FehlerCode=GetLastError();}
         if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
         else break;
        }
      if(Ticketnummer==-1)
        {
         FehlerCode=GetLastError();
         string FehlerBeschreibung=ErrorDescription(FehlerCode);
         string FehlerAusgabe=StringConcatenate("Eröffnung Limit-Verkauf-Order:",FehlerCode,": ",FehlerBeschreibung);
         sLastError=FehlerAusgabe;
        }
     }
   return(Ticketnummer);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### LoescheAlleBuyStopOrders ################################################
// Löscht alle Buy-Stop Order einer Magicnumber / Symbol - Kombination.
//  
void LoescheAlleBuyStopOrders(string sSymbol,int MagicNumber)
  {
   for(int Zaehler=0; Zaehler<=OrdersTotal()-1; Zaehler++)
     {
      bool Geloescht=false;
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      int FehlerCode = 0;
      bool Orderwahl = OrderSelect(Zaehler, SELECT_BY_POS);
      if(Orderwahl==true && OrderMagicNumber()==MagicNumber && OrderSymbol()==sSymbol && OrderType()==OP_BUYSTOP)
        {
         int LoeschenTicketnummer=OrderTicket();
         while(IsTradeContextBusy()) Sleep(10);
         while(Geloescht==false)
           {
            Geloescht=OrderDelete(LoeschenTicketnummer,Red);
            if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
            else break;
           }
         if(Geloescht==false)
           {
            FehlerCode=GetLastError();
            string FehlerBeschreibung=ErrorDescription(FehlerCode);
            string FehlerAusgabe=StringConcatenate("Löschen Kauf-Stop-Order:",FehlerCode,": ",FehlerBeschreibung);
            sLastError=FehlerAusgabe;
           }
         else Zaehler--;
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### LoescheAlleSellStopOrders ################################################
// Löscht alle Sell-Stop Order einer Magicnumber / Symbol - Kombination.
void LoescheAlleSellStopOrders(string sSymbol,int MagicNumber)
  {
   for(int Zaehler=0; Zaehler<=OrdersTotal()-1; Zaehler++)
     {
      bool Geloescht=false;
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      int FehlerCode = 0;
      bool Orderwahl = OrderSelect(Zaehler, SELECT_BY_POS);
      if(Orderwahl==true && OrderMagicNumber()==MagicNumber && OrderSymbol()==sSymbol && OrderType()==OP_SELLSTOP)
        {
         int LoeschenTicketnummer=OrderTicket();
         while(IsTradeContextBusy()) Sleep(10);
         while(Geloescht==false)
           {
            Geloescht=OrderDelete(LoeschenTicketnummer,Red);
            if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
            else break;
           }
         if(Geloescht==false)
           {
            FehlerCode=GetLastError();
            string FehlerBeschreibung=ErrorDescription(FehlerCode);
            string FehlerAusgabe=StringConcatenate("Löschen Verkauf-Stop-Order:",FehlerCode,": ",FehlerBeschreibung);
            Print(FehlerAusgabe);
           }
         else Zaehler--;
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### SchliesseAlleOrders ################################################
// Schliesst alle Orders einer Magicnumber / Symbol - Kombination.
//
void SchliesseAlleOrders(string sSymbol,int MagicNumber,int iSlippage)
  {
   for(int Zaehler=0; Zaehler<=OrdersTotal()-1; Zaehler++)
     {
      bool Geschlossen=false;
      bool Geloescht=false;
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      int FehlerCode = 0;
      bool Orderwahl = OrderSelect(Zaehler, SELECT_BY_POS);
      if(Orderwahl==true && OrderSymbol()==sSymbol && MagicNumber==OrderMagicNumber())
        {
         if(OrderType()==OP_SELL)
           {
            int SchliesenTicketnummer=OrderTicket();
            double SchliesenPositionsgroesse=OrderLots();
            while(IsTradeContextBusy()) Sleep(10);
            while(Geschlossen==false)
              {
               double Ausstiegspreis=MarketInfo(sSymbol,MODE_ASK);
               Geschlossen=OrderClose(SchliesenTicketnummer,SchliesenPositionsgroesse,Ausstiegspreis,iSlippage,Red);
               if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
               else break;
              }
            if(Geschlossen==false)
              {
               FehlerCode=GetLastError();
               string FehlerBeschreibung=ErrorDescription(FehlerCode);
               string FehlerAusgabe=StringConcatenate("Schliessen Verkauf-Order:",FehlerCode,": ",FehlerBeschreibung);
               sLastError=FehlerAusgabe;
              }
            else Zaehler--;
           }
         else if(OrderType()==OP_BUY)
           {
            int SchliesenTicketnummer=OrderTicket();
            double SchliesenPositionsgroesse=OrderLots();
            while(IsTradeContextBusy()) Sleep(10);
            while(Geschlossen==false)
              {
               double Ausstiegspreis=MarketInfo(sSymbol,MODE_BID);
               Geschlossen=OrderClose(SchliesenTicketnummer,SchliesenPositionsgroesse,Ausstiegspreis,iSlippage,Red);
               if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
               else break;
              }
            if(Geschlossen==false)
              {
               FehlerCode=GetLastError();
               string FehlerBeschreibung=ErrorDescription(FehlerCode);
               string FehlerAusgabe=StringConcatenate("Schliessen Kauf-Order:",FehlerCode,": ",FehlerBeschreibung);
               sLastError=FehlerAusgabe;
              }
            else Zaehler--;
           }
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ###################################################### SchliesseAlleBuyLimitOrders ################################################
// Schliesst alle Buy-Limit Orders einer Magicnumber / Symbol - Kombination.
//
void SchliesseAlleBuyLimitOrders(string sfSymbol,int ifMagicNumber)
  {
   int FehlerCode=0;
   for(int Zaehler=0; Zaehler<=OrdersTotal()-1; Zaehler++)
     {
      bool Geloescht=false;
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      bool Orderwahl=OrderSelect(Zaehler,SELECT_BY_POS);
      if(Orderwahl==true && OrderMagicNumber()==ifMagicNumber && OrderSymbol()==sfSymbol && OrderType()==OP_BUYLIMIT)
        {
         int LoeschenTicketnummer=OrderTicket();
         while(IsTradeContextBusy()) Sleep(10);
         while(Geloescht==false)
           {
            Geloescht=OrderDelete(LoeschenTicketnummer,Red);
            if(Geloescht==false){FehlerCode=GetLastError();}
            if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
            else break;
           }
         if(Geloescht==false)
           {
            FehlerCode=GetLastError();
            string FehlerBeschreibung=ErrorDescription(FehlerCode);
            string FehlerAusgabe=StringConcatenate("Löschen Kauf-Limit-Order:",FehlerCode,": ",FehlerBeschreibung);
            sLastError=FehlerAusgabe;
           }
         else Zaehler--;
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// #################################################### SchliesseAlleSellLimitOrders ##########################################
// Schliesst alle Sell-Limit Orders einer Magicnumber / Symbol - Kombination.
//
void SchliesseAlleSellLimitOrders(string FV_Symbol,int FV_MagicNumber)
  {
   int FehlerCode=0;
   for(int Zaehler=0; Zaehler<=OrdersTotal()-1; Zaehler++)
     {
      bool Geloescht=false;
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      bool Orderwahl=OrderSelect(Zaehler,SELECT_BY_POS);
      if(Orderwahl==true && OrderMagicNumber()==FV_MagicNumber && OrderSymbol()==FV_Symbol && OrderType()==OP_SELLLIMIT)
        {
         int LoeschenTicketnummer=OrderTicket();
         while(IsTradeContextBusy()) Sleep(10);
         while(Geloescht==false)
           {
            Geloescht=OrderDelete(LoeschenTicketnummer,Red);
            if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
            else break;
           }
         if(Geloescht==false)
           {
            FehlerCode=GetLastError();
            string FehlerBeschreibung=ErrorDescription(FehlerCode);
            string FehlerAusgabe=StringConcatenate("Löschen Verkauf-Limit-Order:",FehlerCode,": ",FehlerBeschreibung);
            sLastError=FehlerAusgabe;
           }
         else Zaehler--;
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ####################################################### ModifyOrderTP ######################################################
// Verändert den TakeProfit einer Order (muss noch Überarbeitet werden - Prüfung)
//
int ModifyOrderTP(int iTicketnumber,double CTP,int MagicNumber)
  {
   int cnt;
   for(cnt=0;cnt<=TotalOrdersCount(MagicNumber);cnt++)
     {
      bool Ans=OrderSelect(cnt,SELECT_BY_POS,MODE_TRADES);
      if(OrderType()<=OP_SELL && OrderMagicNumber()==MagicNumber && iTicketnumber==OrderTicket())
        {
         Ans=OrderModify(OrderTicket(),OrderOpenPrice(),OrderStopLoss(),CTP,0,Blue);
         return(0);
        }
     }
   return(1);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------


// ####################################################### NewBar #############################################################
// Prüft, ob eine neue Bar erzeugt wurde 
//
bool NewBar()
  {
   static datetime lastbar;
   datetime curbar=Time[0];
   if(lastbar!=curbar)
     {
      lastbar=curbar;
      return (true);
     }
   else
     {
      return(false);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ####################################################### LogError #############################################################
// Errorlog führen - Aktuell nur Fehlermeldung ausgeben. 
//
bool LogError(string Fehler)
  {
   Alert(Fehler);
   Print(Fehler);
   return(TRUE);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ----------------------------------------------------------------------------------------------------------------------------

// ####################################################### FehlerPruefung #############################################################
// Prüft Fehlercodes auf MT4-Orderfehler 
//
bool FehlerPruefung(int iErrorCode)
  {
   switch(iErrorCode)
     {
      case 4:
         return(true);

      case 128:
         return(true);

      case 136:
         return(true);

      case 137:
         return(true);

      case 138:
         return(true);

      case 146:
         return(true);

      default:
         return(false);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ---------------------------------------------------------------------------------------------------------------------------- 

// ####################################################### PreisAskKaufen #####################################################
// Gibt den Kaufkurs des Symbols zurück
//
double PreisAskKaufen(string sSymbol)
  {
   return(MarketInfo(sSymbol,MODE_ASK));
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ---------------------------------------------------------------------------------------------------------------------------- 

// ####################################################### PreisBidVerkaufen #####################################################
// Gibt den Verkaufskurs des Symbols zurück
//
double PreisBidVerkaufen(string sSymbol)
  {
   return(MarketInfo(sSymbol,MODE_BID));
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ---------------------------------------------------------------------------------------------------------------------------- 

// ####################################################### LetztesHochNachMarkttechnik ###########################################
// Gibt den Kurs des letzten Hochs nach Markttechnik zurück
//
double LetztesHochNachMarkttechnik(string sSymbol,int TimeFrame,int Periode,int Shift,double Offset)
  {
   double dHigh=iHigh(sSymbol,TimeFrame,iHighest(sSymbol,TimeFrame,MODE_HIGH,Periode,Shift));
   if(Offset>0)
     {
      dHigh=dHigh+Offset*point;
     }
   return(dHigh);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ------------------------------------------------------------------------------------------------------------------------------- 

// ####################################################### LetztesTiefNachMarkttechnik ###########################################
// Gibt den Kurs des letzten Tiefs nach Markttechnik zurück
//
double LetztesTiefNachMarkttechnik(string sSymbol,int TimeFrame,int Periode,int Shift,double Offset)
  {
   double dLow=iLow(sSymbol,TimeFrame,iLowest(sSymbol,TimeFrame,MODE_LOW,Periode,Shift));
   if(Offset>0)
     {
      dLow=dLow-Offset*point;
     }
   return(dLow);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ------------------------------------------------------------------------------------------------------------------------------- 

// ####################################################### Spread #######################################################
// Gibt die Differenz zwischen Kauf und Verkaufspreis zurück
//
double Spread(string sSymbol)
  {
   return(NormalizeDouble((PreisAskKaufen(sSymbol)-PreisBidVerkaufen(sSymbol))/point,1));
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ------------------------------------------------------------------------------------------------------------------------------- 

// ####################################################### Alarm #######################################################
// Alarmiert mittels Alert und eventuell zusätzlichen Optionen
//
void Alarm(string Text,int type)
  {
   if(type==1) Alert(Text);
   if(type==2) Print(Text);
   if(type==3) {Alert(Text); Print(Text);}
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ------------------------------------------------------------------------------------------------------------------------------- 

// ####################################################### CalculatePipValue #######################################################
// Berechnet den Pip-Wert in der aktuellen Währung für eine bestimmte Lotgröße
//
double CalculatePipValue(string sSymbol,double dPoint,double dLotSize)
  {
   double PipValue=(((MarketInfo(sSymbol,MODE_TICKVALUE)*dPoint)/MarketInfo(sSymbol,MODE_TICKSIZE))*dLotSize);
   return(PipValue);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// -------------------------------------------------------------------------------------------------------------------------------

// ####################################################### CalculatePointValue #######################################################
// Berechnet den Point-Wert in der aktuellen Währung für eine bestimmte Lotgröße
//
double CalculatePointValue(string sSymbol,double dLotSize)
  {
   double PointValue=(((MarketInfo(sSymbol,MODE_TICKVALUE)*Point)/MarketInfo(sSymbol,MODE_TICKSIZE))*dLotSize);
   return(PointValue);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// -------------------------------------------------------------------------------------------------------------------------------

// ####################################################### CheckCandleType #######################################################
// Prüft anhand des Open und Close-Wertes, ob ein buy, sell oder doji vorliegt
string CheckCandleType(double open,double close)
  {
   if(open>close) return("sell");
   if(close>open) return("buy");
   if(close==open) return("doji");
   return("error");
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// -------------------------------------------------------------------------------------------------------------------------------

// ####################################################### CheckLastTrade #######################################################
// Prüft den letzten Trade in der History darauf, ob er ein Gewinner oder ein Verlierer war

string CheckLastTrade(string sSymbol,int magic)
  {
   string sLastLoss="";
   for(int trade=OrdersHistoryTotal()-1;trade>=0;trade--)
     {
      int ret=OrderSelect(trade,SELECT_BY_POS,MODE_HISTORY);
      if(OrderSymbol()==sSymbol && OrderMagicNumber()==magic)
        {
         if(OrderProfit()<0)
           {
            if(OrderType()==OP_BUY) sLastLoss="BUY LOSS";
            if(OrderType()==OP_SELL) sLastLoss="SELL LOSS";
           }
         if(OrderProfit()==0)
           {
            if(OrderType()==OP_BUY) sLastLoss="BUY BREAKEVEN";
            if(OrderType()==OP_SELL) sLastLoss="SELL BREAKEVEN";
           }
         if(OrderProfit()>0)
           {
            if(OrderType()==OP_BUY) sLastLoss="BUY WIN";
            if(OrderType()==OP_SELL) sLastLoss="SELL WIN";
           }
         break;
        }
     }
   return(sLastLoss);
  }
// -------------------------------------------------------------------------------------------------------------------------------

// ####################################################### ModifyTrailingStop ######################################################
// Verändert den StopLoss einer Order (Übergabe TrailingStop als berechneter Wert)
//
void ModifyTrailingStop(string f_Symbol,double f_TrailingStop,int f_MagicNumber)
  {
   bool TrailStopTicket=false;
   int FehlerCode=0;
   for(int Zaehler=0; Zaehler<=OrdersTotal()-1; Zaehler++)
     {
      int Wiederholungen=0;
      int MaximaleWiederholungen=10;
      bool Orderwahl=OrderSelect(Zaehler,SELECT_BY_POS);
      if(Orderwahl==true && OrderSymbol()==f_Symbol && OrderMagicNumber()==f_MagicNumber)
        {
         if(OrderType()==OP_BUY)
           {
            double TrailStopLoss = NormalizeDouble(f_TrailingStop, (int)MarketInfo(f_Symbol,MODE_DIGITS));
            double AktuellerStop = NormalizeDouble(OrderStopLoss(), (int)MarketInfo(f_Symbol,MODE_DIGITS));
            double AktuellerPreis= NormalizeDouble(MarketInfo(f_Symbol,MODE_BID),(int)MarketInfo(f_Symbol,MODE_DIGITS));
            if(AktuellerStop<TrailStopLoss && AktuellerPreis>TrailStopLoss)
              {
               while(TrailStopTicket==false)
                 {
                  TrailStopTicket=OrderModify(OrderTicket(),OrderOpenPrice(),TrailStopLoss,OrderTakeProfit(),0);
                  if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
                  else break;
                 }

               if(TrailStopTicket==false)
                 {
                  FehlerCode=GetLastError();
                  string FehlerBeschreibung=ErrorDescription(FehlerCode);
                  string FehlerAusgabe=StringConcatenate("TrailingStop Kauf-Order:",FehlerCode,": ",FehlerBeschreibung);
                  Print(FehlerAusgabe);
                 }
              }
           }
         else if(OrderType()==OP_SELL)
           {
            double TrailStopLoss = NormalizeDouble(f_TrailingStop, (int)MarketInfo(OrderSymbol(),MODE_DIGITS));
            double AktuellerStop = NormalizeDouble(OrderStopLoss(), (int)MarketInfo(OrderSymbol(),MODE_DIGITS));
            double AktuellerPreis= NormalizeDouble(MarketInfo(f_Symbol,MODE_ASK),(int)MarketInfo(f_Symbol,MODE_DIGITS));
            if(AktuellerStop>TrailStopLoss && AktuellerPreis<TrailStopLoss)
              {
               while(TrailStopTicket==false)
                 {
                  TrailStopTicket=OrderModify(OrderTicket(),OrderOpenPrice(),TrailStopLoss,OrderTakeProfit(),0);
                  if(Wiederholungen<=MaximaleWiederholungen && FehlerPruefung(FehlerCode)==true) {Wiederholungen++;}
                  else break;
                 }
               if(TrailStopTicket==false)
                 {
                  FehlerCode=GetLastError();
                  string FehlerBeschreibung=ErrorDescription(FehlerCode);
                  string FehlerAusgabe=StringConcatenate("TrailingStop Verkauf-Order:",FehlerCode,": ",FehlerBeschreibung);
                  Print(FehlerAusgabe);
                 }
              }
           }
        }
     }
  }
//Die Funktion "PipWert()"
double PipWert(string f_Symbol)
  {
   double Multiplikator;
   double TickGroesse=MarketInfo(f_Symbol,MODE_TICKSIZE);
   if(TickGroesse==0.00001 || TickGroesse==0.001){Multiplikator=TickGroesse*10;}
   else {Multiplikator=TickGroesse;}

   return(Multiplikator);
  }
//+------------------------------------------------------------------+
