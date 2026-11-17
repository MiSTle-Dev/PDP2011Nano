
/*

  esp32 telnet server proof of concept

*/

#include <string.h>
#include <sys/param.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_log.h"

#include "lwip/err.h"
#include "lwip/sys.h"

#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "lwip/netdb.h"

#include "driver/uart.h"
#include "app_uart.h"

#include "app_telnetd.h"

static const char *TAG = "app_telnetd";

#define PORT 23

#define TS_DATA         0       /* base state */
#define TS_IAC          1       /* look for double IAC's */
#define TS_CR           2       /* CR-LF ->'s CR */
#define TS_SB           3       /* throw away begin's... */
#define TS_SE           4       /* ...end's (suboption negotiation) */
#define TS_WILL         5       /* will option negotiation */
#define TS_WONT         6       /* wont " */
#define TS_DO           7       /* do " */
#define TS_DONT         8       /* dont " */
#define TS_CMD          9       /* command from user */
#define TS_SBSKIP      10       // skip sb through se, not handling this
#define TS_NAWS        11       // window (screen) size negotiation
#define TS_TTYPE       12       // terminal type negotiation
#define TS_NEWENV      13       // environment vars
#define CMDCHAR         1

#define IAC     255             /* interpret as command: */
#define DONT    254             /* you are not to use option */
#define DO      253             /* please, you use option */
#define WONT    252             /* I won't use option */
#define WILL    251             /* I will use option */
#define SB      250             /* interpret as subnegotiation */
#define GA      249             /* you may reverse the line */
#define EL      248             /* erase the current line */
#define EC      247             /* erase the current character */
#define AYT     246             /* are you there */
#define AO      245             /* abort output--but let prog finish */
#define IP      244             /* interrupt process--permanently */
#define BREAK   243             /* break */
#define DM      242             /* data mark--for connect. cleaning */
#define NOP     241             /* nop */
#define SE      240             /* end sub negotiation */
#define EOR     239             /* end of record (transparent mode) */

#define SYNCH   242             /* for telfunc calls */

/* telnet options */

#define TELOPT_BINARY   0       /* 8-bit data path */

#define TELOPT_ECHO     1       /* echo */
#define TELOPT_RCP      2       /* prepare to reconnect */
#define TELOPT_SGA      3       /* suppress go ahead */
#define TELOPT_NAMS     4       /* approximate message size */
#define TELOPT_STATUS   5       /* give status */
#define TELOPT_TM       6       /* timing mark */
#define TELOPT_RCTE     7       /* remote controlled transmission and echo */
#define TELOPT_NAOL     8       /* negotiate about output line width */
#define TELOPT_NAOP     9       /* negotiate about output page size */
#define TELOPT_NAOCRD   10      /* negotiate about CR disposition */
#define TELOPT_NAOHTS   11      /* negotiate about horizontal tabstops */
#define TELOPT_NAOHTD   12      /* negotiate about horizontal tab disposition */
#define TELOPT_NAOFFD   13      /* negotiate about formfeed disposition */
#define TELOPT_NAOVTS   14      /* negotiate about vertical tab stops */
#define TELOPT_NAOVTD   15      /* negotiate about vertical tab disposition */
#define TELOPT_NAOLFD   16      /* negotiate about output LF disposition */
#define TELOPT_XASCII   17      /* extended ascic character set */
#define TELOPT_LOGOUT   18      /* force logout */
#define TELOPT_BM       19      /* byte macro */
#define TELOPT_DET      20      /* data entry terminal */
#define TELOPT_SUPDUP   21      /* supdup protocol */
#define TELOPT_SUPDUPOUTPUT 22  /* supdup output */
#define TELOPT_SNDLOC   23      /* send location */
#define TELOPT_TTYPE    24      /* terminal type */
#define TELOPT_EOR      25      /* end or record */
#define TELOPT_TUID     26      /* TACACS user identification */
#define TELOPT_OUTMRK   27      /* output marking */
#define TELOPT_TTYLOC   28      /* terminal location number */
#define TELOPT_3270REGIME 29    /* 3270 regime */
#define TELOPT_X3PAD    30      /* X.3 PAD */
#define TELOPT_NAWS     31      /* window size */
#define TELOPT_TSPEED   32      /* terminal speed */
#define TELOPT_LFLOW    33      /* remote flow control */
#define TELOPT_LINEMODE 34
#define TELOPT_XDISPLOC 35
#define TELOPT_ENVIRON  36
#define TELOPT_AUTH     37
#define TELOPT_ENCRYPT  38
#define TELOPT_NEWENV   39

#define TELOPT_EXOPL    255     /* extended-options-list */

#define NTELOPTS        (1+TELOPT_NEWENV)
char *telopts[NTELOPTS] = {
   "BINARY", "ECHO", "RCP", "SUPPRESS GO AHEAD", "NAME",
   "STATUS", "TIMING MARK", "RCTE", "NAOL", "NAOP",
   "NAOCRD", "NAOHTS", "NAOHTD", "NAOFFD", "NAOVTS",
   "NAOVTD", "NAOLFD", "EXTEND ASCII", "LOGOUT", "BYTE MACRO",
   "DATA ENTRY TERMINAL", "SUPDUP", "SUPDUP OUTPUT",
   "SEND LOCATION", "TERMINAL TYPE", "END OF RECORD",
   "TACACS UID", "OUTPUT MARKING", "TTYLOC",
   "3270 REGIME", "X.3 PAD", "NAWS", "TSPEED", "LFLOW",
   "LINEMODE", "XDISPLOC", "ENVIRON", "AUTHENTICATION",
   "ENCRYPT", "NEW-ENVIRON"
};

struct telnetd_data session[MAX_SESSION];

void telnetd_send(struct telnetd_data *p, char *buf, int buflen)
{
   int err;

   err = send(p->sock, buf, buflen, 0);
   if (err < 0) {
      ESP_LOGE(TAG, "%d error occurred during sending: errno %d", p->sock, errno);
   }
}

void telnetd_list(struct telnetd_data *p)
{
   char *l;
   int i;
   int active;

   active=0;
   for (i=0; i<MAX_SESSION; i++) {
      if (session[i].sock!=0) {
         active++;
      }
   }
   snprintf(p->tx_buffer, sizeof(p->tx_buffer)-1, "\r\n\r\nWelcome %s:%s... %d/%d sessions\r\n",
      p->dispaddr, p->dispport, active, MAX_SESSION);
   telnetd_send(p, p->tx_buffer, strlen(p->tx_buffer));
   for (i=0; i<MAX_SESSION; i++) {
      if (session[i].sock!=0) {
         if (session[i].uart==uart2) {
            l="cons";
         } else if (session[i].uart==uart1) {
            l="line";
         } else {
            l="";
         }
         snprintf(p->tx_buffer, sizeof(p->tx_buffer)-1, "%2d %15s:%-5s (%d) %4s %s\r\n", i, session[i].dispaddr, session[i].dispport, session[i].sock,
            l, &session[i]==p?"(me)":"");
         telnetd_send(p, p->tx_buffer, strlen(p->tx_buffer));
      }
   }
   snprintf(p->tx_buffer, sizeof(p->tx_buffer)-1, "\r\n");
   telnetd_send(p, p->tx_buffer, strlen(p->tx_buffer));
}


void telnetd_cmd(struct telnetd_data *p, char c)
{
   char *line="(line)\r\n";
   char *cons="(cons)\r\n";
   char *nc="(not connected)\r\n";

   if (c=='c') {
      p->uart=uart2;
      telnetd_send(p, cons, strlen(cons));
      return;
   }
   if (c=='l') {
      p->uart=uart1;
      telnetd_send(p, line, strlen(line));
      return;
   }
   if (c=='z') {
      p->uart=-1;
      telnetd_list(p);
      return;
   }
   if (c=='?') {
      telnetd_list(p);
      return;
   }
   telnetd_send(p, nc, strlen(nc));
}


static void telnetd_task(void *pvParameters)
{
   int i;
   char c;
   static int sbcount;

   static int nawsx = 0;
   static int nawsy = 0;

   static char termtype[64]="";

   static char newenv[64]="";

   struct telnetd_data *p;
   static char openingbid[] = {
      IAC, WILL, TELOPT_SGA,    IAC, DO,   TELOPT_SGA,
      IAC, WILL, TELOPT_ECHO,   IAC, DONT, TELOPT_ECHO,
      IAC, WONT, TELOPT_TTYPE,  IAC, DO,   TELOPT_TTYPE,
      IAC, WONT, TELOPT_NAWS,   IAC, DO,   TELOPT_NAWS,
      IAC, WONT, TELOPT_TSPEED, IAC, DONT, TELOPT_TSPEED,
      IAC, WONT, TELOPT_LFLOW,  IAC, DONT, TELOPT_LFLOW,
      IAC, WONT, TELOPT_LINEMODE,  IAC, DONT, TELOPT_LINEMODE,
      IAC, WONT, TELOPT_ENVIRON, IAC, DO,   TELOPT_ENVIRON,
      IAC, WONT, TELOPT_NEWENV, IAC, DO,   TELOPT_NEWENV
   };

   p= (struct telnetd_data *) pvParameters;
   ESP_LOGI(TAG, "%d task started for %s", p->sock, p->dispaddr);

   p->rcvstate = TS_DATA;
   telnetd_send(p, openingbid, sizeof(openingbid));

   telnetd_list(p);

   sbcount = 0;
   while (1) {
      int len;

      len=recv(p->sock, p->rx_buffer, sizeof(p->rx_buffer) - 1, 0);
      if (len < 0) {
         if (errno==EAGAIN || errno==EWOULDBLOCK) {
            continue;
         }
         ESP_LOGE(TAG, "%d recv failed: errno %d", p->sock, errno);
         break;
      }
      if (len == 0) {
         ESP_LOGI(TAG, "%d connection closed", p->sock);
         break;
      }

      p->rx_buffer[len] = 0;
      for (i=0; i<len; i++) {
         c=p->rx_buffer[i];

         switch (p->rcvstate) {

            case TS_DATA:
               if (c==IAC) {
                  p->rcvstate = TS_IAC;
                  continue;
               }
               if (p->uart!=-1) {
                  if (c==CMDCHAR) {
                     p->rcvstate = TS_CMD;
                  } else {
                     if (c) {
                        uart_write_bytes(p->uart, (const char *) &c, 1);
                     }
                  }
               } else {
                  telnetd_cmd(p, c);
               }
               continue;

            case TS_CMD:
               telnetd_cmd(p, c);
               p->rcvstate = TS_DATA;
               continue;

            case TS_IAC:
               switch (c) {

                  case WILL:
                     p->rcvstate = TS_WILL;
                     continue;

                  case WONT:
                     p->rcvstate = TS_WONT;
                     continue;

                  case DO:
                     p->rcvstate = TS_DO;
                     continue;

                  case DONT:
                     p->rcvstate = TS_DONT;
                     continue;

                  case AYT:
                  {
                     char *ayt="\r\n[yes I am here]\r\n\r\n";

                     ESP_LOGI(TAG, "%d AYT", p->sock);
                     telnetd_send(p, ayt, strlen(ayt));
                     p->rcvstate = TS_DATA;
                     continue;
                  }

                  case AO:
                  {
                     ESP_LOGI(TAG, "%d IAC Abort Output", p->sock);
                     p->rcvstate = TS_DATA;
                     continue;
                  }

                  case IP:
                  {
                     ESP_LOGI(TAG, "%d IAC Interrupt Process", p->sock);
                     p->rcvstate = TS_DATA;
                     continue;
                  }

                  case BREAK:
                  {
                     ESP_LOGI(TAG, "%d IAC BREAK", p->sock);
                     p->rcvstate = TS_DATA;
                     continue;
                  }

                  case SB:
                  {
//                     ESP_LOGI(TAG, "%d IAC SB", p->sock);
                     p->rcvstate = TS_SB;
                     continue;
                  }

                  default:
                     ESP_LOGI(TAG, "%d don't know how to handle IAC %d", p->sock, c);
                     p->rcvstate = TS_DATA;
                     continue;
               }
               continue;


            case TS_DO:
               if (c < NTELOPTS) {
                  ESP_LOGI(TAG, "%d DO %s", p->sock, telopts[(int) c]);
               } else {
                  ESP_LOGI(TAG, "%d DO %d", p->sock, (int) c);
               }
               p->rcvstate = TS_DATA;
               continue;

            case TS_DONT:
               if (c < NTELOPTS) {
                  ESP_LOGI(TAG, "%d DONT %s", p->sock, telopts[(int) c]);
               } else {
                  ESP_LOGI(TAG, "%d DONT %d", p->sock, (int) c);
               }
               p->rcvstate = TS_DATA;
               continue;

            case TS_WILL:
               if (c < NTELOPTS) {
                  ESP_LOGI(TAG, "%d WILL %s", p->sock, telopts[(int) c]);
               } else {
                  ESP_LOGI(TAG, "%d WILL %d", p->sock, (int) c);
               }
               p->rcvstate = TS_DATA;
               if ((int) c == TELOPT_TTYPE) {
                  static char telopt_ttype[] = {
                     IAC, SB, TELOPT_TTYPE, 1, IAC, SE
                  };
                  telnetd_send(p, telopt_ttype, sizeof(telopt_ttype));
               }
               if ((int) c == TELOPT_NEWENV) {
                  static char telopt_newenv[] = {
                     IAC, SB, TELOPT_NEWENV, 1, IAC, SE
                  };
                  telnetd_send(p, telopt_newenv, sizeof(telopt_newenv));
               }
               continue;

            case TS_WONT:
               if (c < NTELOPTS) {
                  ESP_LOGI(TAG, "%d WONT %s", p->sock, telopts[(int) c]);
               } else {
                  ESP_LOGI(TAG, "%d WONT %d", p->sock, (int) c);
               }
               p->rcvstate = TS_DATA;
               continue;

            case TS_SB:
               if (c == TELOPT_NAWS) {
                  p->rcvstate = TS_NAWS;
                  sbcount = 0;
                  nawsx = 0;
                  nawsy = 0;
                  continue;
               }
               if (c == TELOPT_TTYPE) {
                  p->rcvstate = TS_TTYPE;
                  sbcount = 0;
                  continue;
               }
               if (c == TELOPT_NEWENV) {
                  p->rcvstate = TS_NEWENV;
                  sbcount = 0;
                  continue;
               }
               if (c < NTELOPTS) {
                  ESP_LOGI(TAG, "%d SB %s", p->sock, telopts[(int) c]);
               } else {
                  ESP_LOGI(TAG, "%d SB %d", p->sock, (int) c);
               }
               p->rcvstate = TS_SBSKIP;
               continue;

            case TS_NAWS:
               sbcount++;
               switch (sbcount) {
                  case 1:
                     nawsy=c * 256;
                     continue;
                  case 2:
                     nawsy+=c;
                     continue;
                  case 3:
                     nawsx=c * 256;
                     continue;
                  case 4:
                     nawsx+=c;
                     continue;
                  default:
               }
               if (c == SE) {
                  ESP_LOGI(TAG, "%d NAWS %d %d", p->sock, nawsy, nawsx);
                  p->rcvstate = TS_DATA;
               }
               continue;

            case TS_TTYPE:
               if (c != SE) {
                  if (c == IAC) {
                     continue;
                  }
                  if (isprint(c)) {
                     termtype[sbcount] = tolower((char) c);
                     sbcount++;
                     if (sbcount > sizeof(termtype)-1) {
                        sbcount = sizeof(termtype)-1;
                     }
                     termtype[sbcount] = '\0';
                  }
               } else {
                  ESP_LOGI(TAG, "%d TTYPE = '%s'", p->sock, termtype);
                  p->rcvstate = TS_DATA;
               }
               continue;

            case TS_NEWENV:
               if (c != SE) {
                  if (c == 0 || c == 3) {
                     newenv[sbcount++] = '>';
                     if (sbcount > sizeof(newenv)-1) {
                        sbcount = sizeof(newenv)-1;
                     }
                     newenv[sbcount] = '\0';
                     continue;
                  }
                  if (c == 1) {
                     newenv[sbcount++] = '=';
                     if (sbcount > sizeof(newenv)-1) {
                        sbcount = sizeof(newenv)-1;
                     }
                     newenv[sbcount] = '\0';
                     continue;
                  }
                  if (c == IAC) {
                     continue;
                  }
                  if (c) {
                     newenv[sbcount] = ((char) c);
                     sbcount++;
                     if (sbcount > sizeof(newenv)-1) {
                        sbcount = sizeof(newenv)-1;
                     }
                     newenv[sbcount] = '\0';
                     continue;
                  }
               } else {
                  ESP_LOGI(TAG, "%d NEWENV = '%s'", p->sock, newenv);
                  p->rcvstate = TS_DATA;
               }
               continue;

            case TS_SBSKIP:
               if (c == SE) {
                  p->rcvstate = TS_DATA;
               }
               continue;

            default:
               p->rcvstate = TS_DATA;
         }
      }
   }
   ESP_LOGI(TAG, "%d shutting down socket for %s", p->sock, p->dispaddr);
   shutdown(p->sock, 0);
   close(p->sock);
   memset(p, 0, sizeof(struct telnetd_data));
   vTaskDelete(NULL);
}

void app_telnetd(void *pv)
{
   char addr_str[128];
   int addr_family;
   int ip_protocol;
   struct sockaddr_in dest_addr;
   int listen_sock;
   int err;
   struct telnetd_data *p;
   int i;
   static char *nospace="\n\r\n\rSorry, table is full, no space for more sessions :-/\n\r\n\r";

   memset(&session, 0, sizeof(session));
   ESP_LOGI(TAG, "sizeof session=%d", sizeof(session));

   dest_addr.sin_addr.s_addr = htonl(INADDR_ANY);
   dest_addr.sin_family = AF_INET;
   dest_addr.sin_port = htons(PORT);
   addr_family = AF_INET;
   ip_protocol = IPPROTO_IP;
   inet_ntoa_r(dest_addr.sin_addr, addr_str, sizeof(addr_str) - 1);

   listen_sock = socket(addr_family, SOCK_STREAM, ip_protocol);
   if (listen_sock < 0) {
      ESP_LOGE(TAG, "Unable to create socket: errno %d", errno);
      return;
   }
   ESP_LOGI(TAG, "Socket created");

   err = bind(listen_sock, (struct sockaddr *)&dest_addr, sizeof(dest_addr));
   if (err != 0) {
      ESP_LOGE(TAG, "Socket unable to bind: errno %d", errno);
      return;
   }
   ESP_LOGI(TAG, "Socket bound, port %d", PORT);

   err = listen(listen_sock, 1);
   if (err != 0) {
      ESP_LOGE(TAG, "Error occurred during listen: errno %d", errno);
      return;
   }
   ESP_LOGI(TAG, "Socket listening");

   while (1) {
      struct sockaddr_in6 source_addr; // Large enough for both IPv4 or IPv6
      socklen_t addr_len = sizeof(source_addr);
      int sock;
      int one = 1;

      sock = accept(listen_sock, (struct sockaddr *) &source_addr, &addr_len);
      if (sock < 0) {
         ESP_LOGE(TAG, "Unable to accept connection: errno %d", errno);
         continue;
      }
      setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
      p=NULL;
      for (i=0; i<MAX_SESSION; i++) {
         if (session[i].sock==0) {
            p=&session[i];
            break;
         }
      }
      if (p==NULL) {
         ESP_LOGI(TAG, "%d no room for new session, table full", sock);
         send(sock, nospace, strlen(nospace)-1, 0);
         shutdown(sock, 0);
         close(sock);
         continue;
      }
      memset(p, 0, sizeof(struct telnetd_data));
      p->sock = sock;
      p->uart = -1;
      // Convert ip address to string
      if (source_addr.sin6_family == PF_INET) {
         inet_ntoa_r(((struct sockaddr_in *)&source_addr)->sin_addr.s_addr, p->dispaddr, sizeof(p->dispaddr) - 1);
         snprintf(p->dispport, sizeof(p->dispport), "%d", ntohs(((struct sockaddr_in *) &source_addr)->sin_port));
      } else if (source_addr.sin6_family == PF_INET6) {
         inet6_ntoa_r(source_addr.sin6_addr, p->dispaddr, sizeof(p->dispaddr) - 1);
         snprintf(p->dispport, sizeof(p->dispport), "%d", ntohs(source_addr.sin6_port));
      }

      ESP_LOGI(TAG, "%d new socket accepted", sock);
      xTaskCreate(telnetd_task, "telnet_session", 4096, (void *) p, 14, NULL);
   }

}
