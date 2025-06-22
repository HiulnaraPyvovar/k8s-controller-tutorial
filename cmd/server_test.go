package cmd

import (
	"testing"
)

func TestServerCommandDefined(t *testing.T) {
	// Check if the server command is defined
	if serverCmd == nil {
		t.Fatal("serverCmd is not defined")
	}

	// Check if the server command has the expected use case
	if serverCmd.Use != "server" {
		t.Errorf("Expected serverCmd.Use to be 'server', got '%s'", serverCmd.Use)
	}

	portFlag := serverCmd.Flags().Lookup("port")
	if portFlag == nil {
		t.Error("Expected 'port' flag to be defined")
	}
}
