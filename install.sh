#!/bin/bash
set -e

echo "Building brain..."
xcodebuild build -scheme brain -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .derived \
  2>&1 | grep -E "(error:|warning:|BUILD)" || true

if [ ! -f ".derived/Build/Products/Release/brain" ]; then
  echo "Build failed!"
  exit 1
fi

echo "Installing..."
mkdir -p ~/.local/bin ~/.local/lib/brain ~/.config/brain/skills

cp .derived/Build/Products/Release/brain ~/.local/lib/brain/
cp -r .derived/Build/Products/Release/mlx-swift_Cmlx.bundle ~/.local/lib/brain/ 2>/dev/null || true

cat > ~/.local/bin/brain << 'EOF'
#!/bin/bash
exec ~/.local/lib/brain/brain "$@"
EOF
chmod +x ~/.local/bin/brain

# Copy skills
if [ -d "skills" ]; then
  cp -n skills/*.json ~/.config/brain/skills/ 2>/dev/null || true
fi

echo ""
echo "Installed! Make sure ~/.local/bin is in your PATH:"
echo ""
echo '  export PATH="$HOME/.local/bin:$PATH"'
echo ""
echo "Then run:"
echo ""
echo '  brain "Hello!"'
echo ""
