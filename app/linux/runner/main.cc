#include <stdlib.h>
#include "my_application.h"

int main(int argc, char** argv) {
  // Disable AT-SPI bridge by default to prevent D-Bus synchronous focus deadlocks
  // with Caribou / accessibility daemons on Linux Mint / Cinnamon / GNOME.
  setenv("NO_AT_BRIDGE", "1", 0);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
