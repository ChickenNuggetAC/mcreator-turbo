package net.chickennuggetac.regenparallel;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Properties;

public final class RegenParallelAgent {

	static final String[] TARGETS = {
			"net/mcreator/generator/template/base/BaseDataModelProvider",
			"net/mcreator/generator/template/MinecraftCodeProvider",
			"net/mcreator/generator/Generator",
			"net/mcreator/workspace/elements/ModElementManager",
			"net/mcreator/element/types/Procedure",
			"net/mcreator/ui/action/impl/workspace/RegenerateCodeAction",
	};

	private RegenParallelAgent() {
	}

	public static void premain(String args, Instrumentation inst) {
		install(args, inst, "premain");
	}

	public static void agentmain(String args, Instrumentation inst) {
		install(args, inst, "agentmain");
	}

	private static void install(String args, Instrumentation inst, String entry) {
		final AgentLog log = new AgentLog(args);
		log.line(entry + " " + nowStamp());

		final Map<String, byte[]> patched = new HashMap<>();
		final Map<String, String> pins = new LinkedHashMap<>();
		try {
			loadPins(pins);
			for (String t : TARGETS) {
				byte[] b = loadResource("/patched/" + t + ".class");
				if (b == null) {
					log.line("missing patched class: " + t);
				} else {
					patched.put(t, b);
				}
				if (!pins.containsKey(t))
					log.line("missing pin: " + t);
			}
		} catch (Exception e) {
			log.line("load failed: " + e);
			log.flush();
			return;
		}

		final ClassFileTransformer transformer = new ClassFileTransformer() {
			@Override public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
					ProtectionDomain protectionDomain, byte[] classfileBuffer) {
				if (className == null)
					return null;
				if (!patched.containsKey(className) || !pins.containsKey(className))
					return null;

				String expected = pins.get(className);
				String actual;
				try {
					actual = sha256hex(classfileBuffer);
				} catch (Exception e) {
					log.line("hash failed " + className + ": " + e);
					return null;
				}

				if (!expected.equalsIgnoreCase(actual)) {
					log.line("pin mismatch " + className);
					return null;
				}

				byte[] replacement = patched.get(className);
				log.line("swap " + className);
				return replacement;
			}
		};

		inst.addTransformer(transformer, false);
		log.line("registered " + pins.size() + "/" + TARGETS.length + " pins, " + patched.size() + " patched");
		log.flush();
	}

	static byte[] loadResource(String path) throws IOException {
		try (InputStream in = RegenParallelAgent.class.getResourceAsStream(path)) {
			if (in == null)
				return null;
			ByteArrayOutputStream bos = new ByteArrayOutputStream(64 * 1024);
			byte[] buf = new byte[8192];
			int r;
			while ((r = in.read(buf)) != -1)
				bos.write(buf, 0, r);
			return bos.toByteArray();
		}
	}

	static void loadPins(Map<String, String> out) throws IOException {
		try (InputStream in = RegenParallelAgent.class.getResourceAsStream("/patched/pins.properties")) {
			if (in == null)
				throw new IOException("/patched/pins.properties not found in agent jar");
			Properties p = new Properties();
			p.load(in);
			for (String key : p.stringPropertyNames())
				out.put(key.trim(), p.getProperty(key).trim());
		}
	}

	static String sha256hex(byte[] data) throws Exception {
		MessageDigest md = MessageDigest.getInstance("SHA-256");
		byte[] d = md.digest(data);
		StringBuilder sb = new StringBuilder(d.length * 2);
		for (byte b : d) {
			int v = b & 0xff;
			if (v < 16)
				sb.append('0');
			sb.append(Integer.toHexString(v));
		}
		return sb.toString();
	}

	private static String nowStamp() {
		return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
	}

	static final class AgentLog {
		private final StringBuilder buf = new StringBuilder();
		private final Path file;

		AgentLog(String args) {
			Path resolved = null;
			try {
				String explicit = null;
				if (args != null && !args.isBlank()) {
					for (String part : args.split(",")) {
						int eq = part.indexOf('=');
						if (eq > 0 && part.substring(0, eq).trim().equalsIgnoreCase("log"))
							explicit = part.substring(eq + 1).trim();
					}
				}
				if (explicit != null) {
					resolved = Paths.get(explicit);
				} else {
					String home = System.getProperty("user.home", ".");
					resolved = Paths.get(home, ".mcreator", "regen_parallel_agent.log");
				}
				Files.createDirectories(resolved.getParent());
			} catch (Exception e) {
				resolved = null;
			}
			this.file = resolved;
		}

		void line(String s) {
			buf.append(s).append(System.lineSeparator());
			PrintStream err = System.err;
			err.println("[regen_parallel_agent] " + s);
		}

		void flush() {
			if (file == null)
				return;
			try {
				Files.write(file, buf.toString().getBytes(StandardCharsets.UTF_8),
						StandardOpenOption.CREATE, StandardOpenOption.APPEND);
			} catch (Exception ignored) {
			}
			buf.setLength(0);
		}
	}
}
