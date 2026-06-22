package net.chickennuggetac.fastsave;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.security.ProtectionDomain;
import java.util.Date;

import javassist.ByteArrayClassPath;
import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtMethod;
import javassist.CannotCompileException;
import javassist.expr.ExprEditor;
import javassist.expr.MethodCall;

public final class FastSaveAgent {

	private static final String TARGET_INTERNAL = "net/mcreator/ui/modgui/ModElementGUI";
	private static final String TARGET_DOTTED = "net.mcreator.ui.modgui.ModElementGUI";
	private static final String GEN_CLASS = "net.mcreator.generator.Generator";
	private static final String GEN_METHOD = "generateBase";

	public static void premain(String args, Instrumentation inst) {
		log("loaded");
		inst.addTransformer(new SkipBaseGenTransformer(), false);
	}

	public static void agentmain(String args, Instrumentation inst) {
		premain(args, inst);
		try {
			for (Class<?> c : inst.getAllLoadedClasses()) {
				if (TARGET_DOTTED.equals(c.getName())) {
					inst.retransformClasses(c);
				}
			}
		} catch (Throwable t) {
			log("retransform-on-attach failed (" + t + ")");
		}
	}

	static final class SkipBaseGenTransformer implements ClassFileTransformer {
		@Override
		public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
				ProtectionDomain protectionDomain, byte[] classfileBuffer) {
			if (className == null || !className.equals(TARGET_INTERNAL)) return null;
			return patch(classfileBuffer);
		}
	}

	static byte[] patch(byte[] classfileBuffer) {
		try {
			ClassPool cp = new ClassPool(true);
			cp.appendClassPath(new ByteArrayClassPath(TARGET_DOTTED, classfileBuffer));
			CtClass cc = cp.get(TARGET_DOTTED);
			CtMethod m = cc.getDeclaredMethod("finishModCreation");
			final boolean[] patched = {false};
			m.instrument(new ExprEditor() {
				@Override
				public void edit(MethodCall call) throws CannotCompileException {
					if (GEN_CLASS.equals(call.getClassName()) && GEN_METHOD.equals(call.getMethodName())) {
						call.replace("$_ = true;");
						patched[0] = true;
					}
				}
			});
			if (!patched[0]) {
				log("generateBase() not found in finishModCreation; unmodified");
				cc.detach();
				return null;
			}
			byte[] out = cc.toBytecode();
			cc.detach();
			log("patched finishModCreation");
			return out;
		} catch (Throwable t) {
			log("transform failed: " + t);
			return null;
		}
	}

	private static void log(String msg) {
		String line = "[CneFastSave] " + msg;
		System.out.println(line);
		try {
			Path p = Paths.get(System.getProperty("user.home"), ".mcreator", "cne_fastsave.log");
			Files.write(p,
					(new Date() + "  " + line + System.lineSeparator()).getBytes(StandardCharsets.UTF_8),
					StandardOpenOption.CREATE, StandardOpenOption.APPEND);
		} catch (Throwable ignored) {
		}
	}

	public static void main(String[] argv) throws Exception {
		if (argv.length != 2) {
			System.out.println("usage: FastSaveAgent <ModElementGUI.class in> <out.class>");
			System.exit(64);
		}
		byte[] in = Files.readAllBytes(Paths.get(argv[0]));
		byte[] out = patch(in);
		if (out == null) {
			System.out.println("RESULT: no transform applied");
			System.exit(2);
		}
		Files.write(Paths.get(argv[1]), out);
		System.out.println("RESULT: wrote " + out.length + " bytes (in was " + in.length + ")");
	}
}
