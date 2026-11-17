
#ifndef INCL_APP_TELNETD_H
#define INCL_APP_TELNETD_H

void app_telnetd(void *pv);

struct telnetd_data {
   int sock;
   char dispaddr[48];
   char dispport[16];
   char rx_buffer[160];
   char tx_buffer[160];
   int rcvstate;
   int uart;
};

#define MAX_SESSION 10
extern struct telnetd_data session[];

void telnetd_send(struct telnetd_data *p, char *buf, int buflen);

#endif

