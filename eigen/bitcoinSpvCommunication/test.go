package bitcoin

import (
	"fmt"
	"os/exec"
)

func SendTx(signatures []string) {
	cmdArgs := append([]string{"./send.js"}, signatures...)

	cmd := exec.Command("node", cmdArgs...)

	opt, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Println("Error executing command:", err)
		fmt.Println("Error executing command2:", string(opt))
		return
	}
}

func SignTx(destAddress string, amount string) string {
	// Command to run
	cmd := exec.Command("node", "./app.js",
		"", // Private key
		destAddress,
		"", // multisig
		amount,
		"") // redeemScript

	// Capture the output
	output, err := cmd.CombinedOutput()
	if err != nil {

		fmt.Println("Error executing command:", err)
		fmt.Println("Error executing command:", string(output))
		return ""
	}

	// Store output in a string variable
	outputString := string(output)

	// Print the output
	//fmt.Println("Command Output:")
	//fmt.Println(outputString)

	return outputString

	// You can use the outputString variable as needed
}
