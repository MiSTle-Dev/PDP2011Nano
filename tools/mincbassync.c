

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <fcntl.h>
#include <errno.h>
#include <termios.h>
#include <unistd.h>


int procc(int p, char *filename)
{
   unsigned char msg[80];
   char *c;

   snprintf(msg, sizeof(msg), "\rC%s\r", filename);
   printf("filename='%s'\n", filename);
   write(p, msg, strlen(msg));
}

int prock(int p, char *filename)
{
   char buf[1024];
   FILE *fp;
   unsigned char msg[80];
   char *c;

   snprintf(msg, sizeof(msg), "\rK%s\r", filename);
   printf("filename='%s'\n", filename);
   write(p, msg, strlen(msg));
   usleep(500000);
}

int procr(int p, char *filename)
{
   char buf[64*1024];
   int n;
   int res;
   char *marker;
   int f;

   unsigned char msg[80];

   snprintf(msg, sizeof(msg), "\rR%s\r", filename);
   printf("filename='%s'\n", filename);

   write(p, msg, strlen(msg));
   memset(&buf, '\0', sizeof(buf));

   n = 0;

   while (1) {
      res = read(p, buf+n, sizeof(buf)-n);
      if (res < 0) {
         fprintf(stderr, "Error reading: %s", strerror(errno));
         exit(4);
      }
      n = n + res;
      marker = strstr(buf, "\r\nZ");
      if (marker != NULL) break;
   }
   if (n - 3 != marker - buf) {
      fprintf(stderr, "size mismatch after read\n");
      exit(4);
   }
   n = n - 3;
   if (n < 1) {
      printf("%s: empty file received, skipping write\n", filename);
      return 0;
   }
   f=open(filename, O_CREAT | O_WRONLY | O_TRUNC, 0);
   if (f < 0) {
      fprintf(stderr, "Error opening file %s: %s", filename, strerror(errno));
      exit(4);
   }
   res = write(f, buf, marker-buf);
   if (res < 0) {
      fprintf(stderr, "Error writing file %s: %s", filename, strerror(errno));
      exit(4);
   }
   if (res < marker - buf) {
      fprintf(stderr, "Oops not entire file %s written", filename);
      exit(4);
   }
   close(f);
   printf("%s: read %i bytes, written %i bytes\n", filename, n, res);
   return n;
}

int procw(int p, char *filename)
{
   char buf[1024];
   FILE *fp;
   unsigned char msg[80];
   char *c;

   snprintf(msg, sizeof(msg), "\rW%s\r", filename);
   printf("filename='%s'\n", filename);

   write(p, msg, strlen(msg));
   memset(buf, '\0', sizeof(buf));

   fp=fopen(filename, "r");
   if (fp==NULL) {
      fprintf(stderr, "Error opening file %s: %s", filename, strerror(errno));
      return 0;
   }
   while (1) {
      c=fgets(buf, sizeof(buf), fp);
      if (strlen(buf)<2) {
         fprintf(stderr, "empty line ignored\n");
         continue;
      }
      if (c == NULL) break;
      printf("%s", buf);
      usleep(10000);
      write(p, buf, strlen(buf)-1);
      usleep(10000);
      write(p, "\r", 1);
      usleep(250000);
   }
   fclose(fp);
   write(p, "ZZZ\r", 4);
}

void usage()
{
   fprintf(stderr, "mincbassync [-p portname] -k|-r|-w [-c] file...\n");
}

int main(int argc, char *argv[]) {
   int p;
   struct termios tty;
   int i;
   char ch;
   char portname[64];

   int myflagk = 0;
   int myflagr = 0;
   int myflagw = 0;
   int myflagc = 0;
   char *lastarg = NULL;
   strncpy(portname, "/dev/ttyUSB0", sizeof(portname));

   while ((ch = getopt(argc, argv, "ckrwp:")) != EOF) {
      switch (ch) {
         case 'c':
            myflagc++;
            break;

         case 'k':
            myflagk++;
            break;

         case 'r':
            myflagr++;
            break;

         case 'w':
            myflagw++;
            break;

         case 'p':
            if (strchr(optarg, '/')) {
               snprintf(portname, sizeof(portname), "%s", optarg);
            } else {
               snprintf(portname, sizeof(portname), "/dev/tty%s", optarg);
            }
            break;

         default:
            usage();
            exit(4);
      }
   }
   argc -= optind;
   argv += optind;

   if ((myflagk && (myflagr || myflagw)) || (myflagr && (myflagk || myflagw)) || (myflagw && (myflagk || myflagr))) {
      usage();
      exit(4);
   }

   p = open(portname, O_RDWR);
   if (p<0) {
      fprintf(stderr, "Error opening port\n");
      exit(4);
   }
   if (tcgetattr(p, &tty) != 0) {
      fprintf(stderr, "Error %i from tcgetattr: %s\n", errno, strerror(errno));
      exit(4);
   }

   tty.c_cflag &= ~PARENB;              // no parity
   tty.c_cflag &= ~CSTOPB;              // one stop bit`
   tty.c_cflag &= ~CSIZE;               // clear size bits
   tty.c_cflag |= CS8;                  // set 8 bits
   tty.c_cflag &= ~CRTSCTS;             // no hw flow control
   tty.c_cflag |= CREAD | CLOCAL;       // enable receiver and ignore modem control
   tty.c_lflag &= ~ICANON;              // disable lots of handling we don't need
   tty.c_lflag &= ~ECHO;
   tty.c_lflag &= ~ECHOE;
   tty.c_lflag &= ~ECHONL;
   tty.c_lflag &= ~ISIG;
   tty.c_iflag &= ~(IXON | IXOFF | IXANY);
   tty.c_iflag &= ~(IGNBRK|BRKINT|PARMRK|ISTRIP|INLCR|IGNCR|ICRNL);
   tty.c_oflag &= ~OPOST;
   tty.c_oflag &= ~ONLCR;
   tty.c_cc[VTIME] = 1;                 // set timeout: 0.1 seconds
   tty.c_cc[VMIN] = 0;                  // set minimum characters to return

   cfsetispeed(&tty, B9600);
   cfsetospeed(&tty, B9600);

   if (tcsetattr(p, TCSANOW, &tty) != 0) {
      fprintf(stderr, "Error %i from tcsetattr: %s\n", errno, strerror(errno));
      exit(4);
   }

   while (argc--) {
      if (myflagk) {
         prock(p, *argv);
      }
      if (myflagr) {
         procr(p, *argv);
      }
      if (myflagw) {
         procw(p, *argv);
      }
      lastarg=*argv;
      argv++;
   }
   if (myflagc && lastarg!=NULL) procc(p, lastarg);

   close(p);
   return 0; // success
}
