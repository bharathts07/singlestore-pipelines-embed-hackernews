#!/bin/bash

# SingleStore Hacker News Semantic Search Demo - Full Setup Script
# This script sets up the entire demo environment

set -e  # Exit on error

echo "============================================================================"
echo "SingleStore Hacker News Semantic Search Demo - Full Setup"
echo "============================================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    echo "Please create a .env file based on .env.example"
    echo "  cp .env.example .env"
    echo "  # Edit .env with your SingleStore credentials"
    exit 1
fi

echo -e "${GREEN}✓ Found .env file${NC}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗ Docker is not running${NC}"
    echo "Please start Docker Desktop and try again"
    exit 1
fi

echo -e "${GREEN}✓ Docker is running${NC}"
echo ""

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
    echo -e "${GREEN}✓ Virtual environment created${NC}"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate
echo -e "${GREEN}✓ Virtual environment activated${NC}"
echo ""

# Install Python dependencies for setup script
echo "Installing Python dependencies for setup scripts..."
pip install -q -r scripts/requirements.txt
echo -e "${GREEN}✓ Setup script dependencies installed${NC}"
echo ""

# Run database setup
echo "Setting up SingleStore database..."
python scripts/setup_database.py
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Database setup failed${NC}"
    deactivate
    exit 1
fi
echo ""

# Start HN fetcher
echo "Starting Hacker News fetcher..."
docker-compose up -d
echo -e "${GREEN}✓ HN fetcher started${NC}"
echo ""

# Install dashboard dependencies
echo "Installing dashboard dependencies..."
pip install -q -r dashboard/requirements.txt
echo -e "${GREEN}✓ Dashboard dependencies installed${NC}"
echo ""

echo "============================================================================"
echo -e "${GREEN}✓ Setup completed successfully!${NC}"
echo "============================================================================"
echo ""
echo "Services running:"
echo "  • Fetcher:      docker-compose ps"
echo "  • Dashboard:    http://localhost:5000 (after starting)"
echo ""
echo "To start the dashboard:"
echo "  ${YELLOW}source venv/bin/activate${NC}  # Activate virtual environment first"
echo "  cd dashboard"
echo "  python app.py"
echo ""
echo "To monitor the system:"
echo "  ${YELLOW}source venv/bin/activate${NC}  # Activate virtual environment first"
echo "  python scripts/monitor.py"
echo ""
echo "To view logs:"
echo "  docker-compose logs -f"
echo ""
echo "To stop services:"
echo "  docker-compose down"
echo ""
echo "Note: Virtual environment created in ./venv"
echo "      Always activate it before running Python scripts:"
echo "      ${YELLOW}source venv/bin/activate${NC}"
echo ""
