import asyncio
from playwright.async_api import async_playwright
import os

os.makedirs("output", exist_ok=True)

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(viewport={"width": 1280, "height": 800})
        
        pages = [
            ("http://localhost:8000/index.html", "output/slide_landing.png"),
            ("http://localhost:8000/campinas_presidente_2t.html", "output/slide_presidente.png"),
            ("http://localhost:8000/campinas_governador_1t.html", "output/slide_governador.png")
        ]
        
        for url, path in pages:
            page = await context.new_page()
            print(f"Navigating to {url}...")
            await page.goto(url, wait_until="networkidle")
            await asyncio.sleep(2) # ensure tiles/render complete
            await page.screenshot(path=path, full_page=True)
            print(f"Saved {path}")
            await page.close()
            
        await browser.close()

asyncio.run(main())
