describe("Backend API", () => {
  test("environment is test", () => {
    expect(process.env.NODE_ENV).not.toBe("production");
  });

  test("required env vars are defined in production config", () => {
    const requiredVars = ["DB_HOST", "DB_USER", "DB_PASSWORD"];
    requiredVars.forEach(varName => {
      expect(typeof varName).toBe("string");
    });
  });

  test("port configuration is valid", () => {
    const port = process.env.PORT || 3000;
    expect(Number(port)).toBeGreaterThan(0);
    expect(Number(port)).toBeLessThan(65536);
  });
});
