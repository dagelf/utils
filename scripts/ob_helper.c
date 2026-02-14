#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <keyutils.h>
#include <unistd.h>

# gcc ob_helper.c -o ob_helper -lkeyutils
# sudo strip ob_helper
# sudo chmod 4755 ob_helper

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <encrypted_command>\n", argv[0]);
        return 1;
    }

    // Get key from root's keyring
    key_serial_t key = keyctl_search(KEY_SPEC_USER_KEYRING, "user", "ob_cmd_key", 0);
    if (key == -1) {
        fprintf(stderr, "Key not found\n");
        return 1;
    }
    char key_buffer[256];
    long key_len = keyctl_read(key, key_buffer, sizeof(key_buffer));
    if (key_len == -1) {
        fprintf(stderr, "Failed to read key\n");
        return 1;
    }
    key_buffer[key_len] = '\0';

    // Prepare OpenSSL command to decrypt
    char cmd[1024];
    snprintf(cmd, sizeof(cmd),
             "echo '%s' | openssl aes-256-cbc -pbkdf2 -a -d -salt -k '%s' 2>/dev/null",
             argv[1], key_buffer);

    // Execute decrypted command
    int result = system(cmd);
    return result == 0 ? 0 : 1;
}
