import com.jcraft.jsch.*;
import java.util.Properties;

public class PuttyLikeSSH {

    public static void main(String[] args) {

        String host = "target.server.com";
        int port = 22;
        String user = "myuser";
        String passwordOrOtp = "MyPasswordOrOTP";

        // ===== PROXY (same as PuTTY) =====
        String proxyHost = "proxy.company.com";
        int proxyPort = 1080; // SOCKS usually works best
        String proxyUser = "proxyUser";
        String proxyPass = "proxyPass";

        try {
            JSch jsch = new JSch();

            Session session = jsch.getSession(user, host, port);

            // PuTTY uses keyboard-interactive by default
            session.setConfig("PreferredAuthentications",
                    "keyboard-interactive,password");

            session.setPassword(passwordOrOtp);

            // ---- SOCKS5 Proxy (recommended) ----
            ProxySOCKS5 proxy = new ProxySOCKS5(proxyHost, proxyPort);
            proxy.setUserPasswd(proxyUser, proxyPass);
            session.setProxy(proxy);

            // PuTTY does not fail on unknown hosts
            Properties config = new Properties();
            config.put("StrictHostKeyChecking", "no");
            session.setConfig(config);

            // Keep-alive like PuTTY
            session.setServerAliveInterval(30_000);

            System.out.println("Connecting like PuTTY...");
            session.connect(60_000);

            System.out.println("Connected successfully (PuTTY-style)");

            session.disconnect();

        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}